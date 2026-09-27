package main

import rego.v1

# --- Terraform PLAN JSON: every taggable resource must carry a `version`
# tag matching "<company-name>-<department>:w.x.y.z". ---
#
# This rule targets `terraform show -json <planfile>` output (resource
# values are fully RESOLVED here -- var references like
# "${var.company_version}" are already substituted with real strings,
# unlike scanning raw .tf source, where the string is still a literal
# unresolved interpolation and can never match a semver regex). Run this
# in CI as: terraform show -json tfplan > plan.json && conftest test
# --policy policy plan.json

is_plan_json(doc) if {
	is_object(doc)
	doc.resource_changes
}

plan_resources[addr] = after if {
	is_plan_json(input)
	some rc in input.resource_changes
	after := rc.change.after
	after != null
	addr := rc.address
}

deny contains msg if {
	some addr
	after := plan_resources[addr]
	after.tags
	not after.tags.version
	msg := sprintf(
		"%s: has a `tags` block but is missing the required `tags.version` company-version tag (format: <company-name>-<department>:w.x.y.z)",
		[addr],
	)
}

deny contains msg if {
	some addr
	after := plan_resources[addr]
	v := after.tags.version
	not is_valid_company_version(v)
	msg := sprintf(
		"%s: tags.version = %q does not match required format <company-name>-<department>:w.x.y.z (e.g. \"acme-platform:1.4.0\")",
		[addr, v],
	)
}
