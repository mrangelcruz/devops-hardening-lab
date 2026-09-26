package main

import rego.v1

# --- Ansible: every play must declare a `company_version` var ---
# matching "<company-name>-<department>:w.x.y.z".
#
# IMPORTANT conftest behavior: an Ansible playbook file is a top-level YAML
# array of plays, but conftest treats each array element as its own
# separate input document -- `input` here is a SINGLE play object (it has
# `hosts`/`tasks` keys), never the whole array. Guard on the absence of a
# `resource` key (Terraform's input shape) so this rule never cross-fires
# against .tf files evaluated by the same policy directory.

is_ansible_play(doc) if {
	is_object(doc)
	not doc.resource
	doc.tasks
}

deny contains msg if {
	is_ansible_play(input)
	not object.get(input, "vars", {}).company_version
	name := object.get(input, "name", "<unnamed play>")
	msg := sprintf(
		"play %q: missing required `vars.company_version` (format: <company-name>-<department>:w.x.y.z)",
		[name],
	)
}

deny contains msg if {
	is_ansible_play(input)
	v := object.get(input, "vars", {}).company_version
	v != null
	not is_valid_company_version(v)
	name := object.get(input, "name", "<unnamed play>")
	msg := sprintf(
		"play %q: vars.company_version = %q does not match required format <company-name>-<department>:w.x.y.z (e.g. \"acme-platform:1.4.0\")",
		[name, v],
	)
}
