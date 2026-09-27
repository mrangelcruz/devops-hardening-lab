# AI PR Review Setup

This repo's author uses [Cursor BugBot](https://cursor.com/bugbot) for
automated AI code review on pull requests. A few things worth knowing if
you're evaluating or forking this repo:

## How it's wired up here

BugBot is a **GitHub App**, not a workflow file — there's nothing in
`.github/workflows/` for it, because it's configured through Cursor's
dashboard and tied to a Cursor subscription, not repo code. It's installed
on this specific repository and automatically comments on new PRs with
review feedback (bugs, logic issues, security concerns) as part of the
author's normal PR workflow.

## If you fork this repo

**BugBot will NOT automatically run on your fork** — it's tied to the
original author's Cursor account and GitHub App installation, not
something that travels with the code. To get equivalent AI PR review on
your own fork, you have a few options:

1. **Install Cursor BugBot yourself** (requires a Cursor subscription) —
   see [cursor.com/bugbot](https://cursor.com/bugbot) for setup.
2. **Substitute a different AI review tool**, e.g.:
   - GitHub Copilot's PR review (if you have Copilot access)
   - A custom GitHub Action calling an LLM API (Anthropic, OpenAI, etc.)
     against the PR diff — see `.github/workflows/ci.yml` for where such
     a job would slot in alongside the existing lint/security jobs.
3. **Skip AI review entirely** — the pre-commit hooks, Checkov, Trivy, and
   `terraform plan`-on-PR checks in `ci.yml` provide substantial coverage
   without it; AI review is a complement to those, not a replacement.

## Why this approach for this project

The rest of this pipeline (pre-commit, Checkov, Trivy, OIDC-based
Terraform plan/apply) is fully portable — any forker gets identical
behavior with their own AWS account and GitHub secrets. The AI-review
layer is the one piece that's author-specific by nature (tied to a paid
subscription), so it's documented separately here rather than pretended to
be a turnkey part of the CI workflow.
