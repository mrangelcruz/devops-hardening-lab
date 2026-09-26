# devops-hardening-lab

A small, real (not simulated) AWS + Terraform + Ansible environment built
to demonstrate a production-style DevSecOps pipeline: pre-commit hygiene,
automated security/compliance scanning, PR-visible `terraform plan`, and a
manually-gated `apply` — wrapped around a genuine infrastructure-drift
detection scenario.

**This is designed to be forked and run by anyone with their own AWS
account** — no shared credentials, no long-lived secrets. See
[Running this yourself](#running-this-yourself) below.

## What this demonstrates

- **Terraform**: modular design (`modules/` vs `environments/` — see
  reasoning in `docs/`), remote-state-free local backends for simplicity,
  least-privilege IAM.
- **A real drift-detection scenario**: a legitimate incident-response
  Ansible playbook (`break-glass-enable.yml`) intentionally modifies
  AWS infrastructure outside Terraform's workflow, and this pipeline's CI
  catches it. Full writeup: [`docs/DRIFT-DETECTION.md`](docs/DRIFT-DETECTION.md).
- **CI/CD security tooling**: pre-commit hooks, Checkov, Trivy, and
  `ansible-lint` gate every change before it can reach `main`.
- **Zero-long-lived-credentials CI/CD**: GitHub Actions authenticates to
  AWS via OIDC role assumption — no `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  ever stored as a GitHub secret.
- **A real manual approval gate**: `apply` only runs via `workflow_dispatch`,
  behind a GitHub Environment with a required-reviewer protection rule —
  the actual security boundary lives in repo settings, not workflow YAML.

## Architecture

```
terraform/
├── modules/
│   ├── vpc/            single-subnet VPC, no NAT (keeps cost near-zero)
│   ├── ssm-instance/   EC2 + zero-inbound SG (the drift target) + IAM role
│   ├── bucket/         generic S3 bucket (Ansible SSM relay storage)
│   └── github-oidc/    OIDC provider + plan/apply IAM roles for CI/CD
└── environments/
    ├── bootstrap/              the S3 relay bucket (apply first)
    ├── dev/                    VPC + EC2 instance (the lab environment)
    └── github-oidc-bootstrap/  OIDC setup (apply once, manually, outside CI)

ansible/
├── playbooks/
│   ├── nginx.yml                 idempotent baseline config example
│   ├── break-glass-enable.yml    THE DRIFT SOURCE (see docs/DRIFT-DETECTION.md)
│   └── break-glass-disable.yml   one remediation path
└── inventory.aws_ec2.yml.example

.github/workflows/
├── ci.yml     pre-commit + Checkov + Trivy + terraform plan (PR comment)
└── apply.yml  manual, Environment-gated terraform apply

docs/
├── DRIFT-DETECTION.md   the full scenario writeup
└── AI-PR-REVIEW.md      how PR review is handled (and how to substitute your own)
```

## Why SSM instead of SSH by default

The lab's EC2 instance has no SSH key and a security group with zero
inbound rules — reachable only via AWS Systems Manager Session Manager.
Ansible connects the same way, using the `community.aws.aws_ssm`
connection plugin (SSM's session channel doesn't natively support file
transfer, so it relays through the S3 bucket the `bootstrap` environment
provisions). This isn't incidental — it's the actual security posture the
drift scenario is built around: SSH access is **not** the normal path, it
only exists as a scoped, time-boxed break-glass exception.

## Running this yourself

This costs a small amount of real AWS money if you leave resources
running (a `t3.micro` instance + a tiny S3 bucket — a few cents/hour at
most; no NAT Gateway is used specifically to avoid the ~$32/mo/AZ that
would otherwise dominate the cost). Destroy resources when you're done
(`terraform destroy` in `environments/dev`, then `environments/bootstrap`).

### 1. Fork this repo

### 2. One-time manual setup: OIDC (so CI can authenticate to AWS without stored keys)

```bash
cd terraform/environments/github-oidc-bootstrap
terraform init
terraform apply -var="github_org=YOUR_GITHUB_USERNAME"
```

This creates an IAM OIDC provider + two roles (`plan`: read-only,
`apply`: scoped write access) trusted **only** by GitHub Actions runs from
your specific fork. Note the two output ARNs.

### 3. Set repository variables (not secrets — ARNs aren't sensitive)

In your fork's GitHub repo Settings → Secrets and variables → Actions →
Variables tab:
- `PLAN_ROLE_ARN` = the `plan_role_arn` output from step 2
- `APPLY_ROLE_ARN` = the `apply_role_arn` output from step 2

### 4. Configure the manual-approval gate

Repo Settings → Environments → New environment → name it `production` →
enable **Required reviewers** and add yourself. This is what actually
gates `apply.yml` — the workflow file alone doesn't enforce anything
without this.

### 5. Bootstrap the S3 relay bucket

```bash
cd terraform/environments/bootstrap
terraform init
terraform apply -var="bucket_name=YOUR-UNIQUE-BUCKET-NAME"
```

(S3 bucket names are globally unique across all of AWS — pick something
that includes your username/org.)

### 6. Provision the lab environment

Either locally (`cd terraform/environments/dev && terraform apply`), or
via this repo's own `apply.yml` workflow (Actions tab → Apply → Run
workflow → type `apply` to confirm).

### 7. Set up Ansible

```bash
cd ansible
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
cp inventory.aws_ec2.yml.example inventory.aws_ec2.yml
# edit inventory.aws_ec2.yml: set ansible_aws_ssm_bucket_name to your
# bootstrap bucket's real name (terraform output bucket_id from step 5)
```

### 8. Try the drift scenario

Follow [`docs/DRIFT-DETECTION.md`](docs/DRIFT-DETECTION.md)'s "Try it
yourself" section.

### 9. Install pre-commit hooks locally (optional but recommended)

```bash
pip install pre-commit
pre-commit install
```

### 10. When you're done — tear it all down

```bash
cd terraform/environments/dev && terraform destroy
cd ../bootstrap && terraform destroy
# github-oidc-bootstrap can stay -- it costs nothing and you'll likely
# reuse it if you come back to this lab later
```

## What's intentionally NOT included

- **No NAT Gateway** — keeps cost near-zero for anyone trying this;
  private subnets weren't needed for this scenario.
- **No Terraform remote state backend (S3 + DynamoDB locking)** — local
  state is fine for a single-person lab; a real team environment would
  need this, but it's out of scope for a fork-and-try demo.
- **BugBot AI review doesn't travel to forks** — see
  [`docs/AI-PR-REVIEW.md`](docs/AI-PR-REVIEW.md) for why and what to
  substitute.
