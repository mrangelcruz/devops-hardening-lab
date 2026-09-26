package main

import rego.v1

# --- Company version format ---
# Required format: <company-name>-<department>:w.x.y.z
# e.g. "acme-platform:1.4.0"
# company-name and department: lowercase alphanumeric, hyphens allowed within
# each segment; the two segments are joined by a single hyphen; version is
# strict semver (three dot-separated non-negative integers, no pre-release
# suffix -- tighten/loosen as your org's semver policy requires).
company_version_pattern := `^[a-z][a-z0-9]*(-[a-z0-9]+)*-[a-z][a-z0-9]*(-[a-z0-9]+)*:[0-9]+\.[0-9]+\.[0-9]+$`

is_valid_company_version(v) if {
	regex.match(company_version_pattern, v)
}
