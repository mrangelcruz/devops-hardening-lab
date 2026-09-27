package main_test

import rego.v1
import data.main

# --- company_version format matcher ---

test_valid_company_version_ok if {
	main.is_valid_company_version("acme-platform:1.4.0")
}

test_valid_company_version_multi_segment_ok if {
	main.is_valid_company_version("acme-corp-platform-team:12.34.56")
}

test_valid_company_version_missing_colon_fails if {
	not main.is_valid_company_version("acme-platform-1.4.0")
}

test_valid_company_version_bad_semver_fails if {
	not main.is_valid_company_version("acme-platform:1.4")
}

test_valid_company_version_no_department_fails if {
	not main.is_valid_company_version("acmeplatform:1.4.0")
}

# --- Terraform (plan JSON): tags.version enforcement is tested in
# policy/terraform_plan_version_tag_test.rego, since that's the input
# shape actually used in CI (terraform show -json <planfile>).

# --- Ansible: vars.company_version enforcement ---
# NOTE: conftest feeds each play in the YAML array as its own separate
# input document (see policy/ansible_version_var.rego comment) -- so unit
# tests mock `input` as a single play object, not the whole array.

test_ansible_play_with_valid_version_passes if {
	count(main.deny) == 0 with input as {
		"name": "good play",
		"hosts": "all",
		"tasks": [{"name": "noop"}],
		"vars": {"company_version": "acme-platform:2.0.1"},
	}
}

test_ansible_play_missing_version_denied if {
	count(main.deny) == 1 with input as {
		"name": "bad play",
		"hosts": "all",
		"tasks": [{"name": "noop"}],
	}
}

test_ansible_play_bad_format_denied if {
	count(main.deny) == 1 with input as {
		"name": "bad play",
		"hosts": "all",
		"tasks": [{"name": "noop"}],
		"vars": {"company_version": "1.4.0"},
	}
}
