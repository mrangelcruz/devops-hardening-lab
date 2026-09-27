package main_test

import rego.v1
import data.main

test_plan_resource_with_valid_version_passes if {
	count(main.deny) == 0 with input as {
		"resource_changes": [{
			"address": "aws_s3_bucket.this",
			"change": {"after": {"tags": {"version": "acme-platform:1.0.0"}}},
		}],
	}
}

test_plan_resource_missing_version_denied if {
	count(main.deny) == 1 with input as {
		"resource_changes": [{
			"address": "aws_s3_bucket.this",
			"change": {"after": {"tags": {"Name": "x"}}},
		}],
	}
}

test_plan_resource_bad_version_denied if {
	count(main.deny) == 1 with input as {
		"resource_changes": [{
			"address": "aws_s3_bucket.this",
			"change": {"after": {"tags": {"version": "1.0.0"}}},
		}],
	}
}

test_plan_resource_without_tags_skipped if {
	count(main.deny) == 0 with input as {
		"resource_changes": [{
			"address": "aws_iam_role_policy.x",
			"change": {"after": {"policy": "{}"}},
		}],
	}
}

test_plan_resource_being_destroyed_skipped if {
	# `change.after` is null when a resource is being destroyed -- must not
	# crash or false-positive on delete-only plans.
	count(main.deny) == 0 with input as {
		"resource_changes": [{
			"address": "aws_s3_bucket.this",
			"change": {"after": null},
		}],
	}
}
