# Drift Detection — the scenario this lab demonstrates

## What "drift" means here

Terraform's `terraform/environments/dev` declares an EC2 instance and a
security group with **zero inbound rules** (`terraform/modules/ssm-instance/main.tf`).
Access is exclusively via AWS Systems Manager Session Manager — no SSH key,
no open port 22, by design.

`ansible/playbooks/break-glass-enable.yml` is a real, legitimate
incident-response tool: when SSM itself is unavailable, it opens a
scoped, temporary SSH ingress rule (one CIDR, never `0.0.0.0/0`), pushes a
60-second ephemeral key via EC2 Instance Connect, and self-schedules its
own revocation via `at`.

**The drift scenario:** that playbook modifies the security group
**directly via the AWS API** — completely outside Terraform's workflow.
Terraform's state file has no record of this change. If the self-scheduled
auto-revoke doesn't fire (the `at` daemon isn't running, the incident was
handled from a different host, an on-call engineer forgot to verify
cleanup), the rule persists indefinitely — a real, live example of
infrastructure drift: reality has diverged from declared state, and
nothing will notice unless someone looks.

## How this repo's CI catches it

Every `terraform plan` run in `.github/workflows/ci.yml` (on every PR, and
on every push to `main`) will surface this exact class of drift: if a
break-glass session was opened and never properly reverted, the next
`terraform plan` shows an unplanned change to the security group resource
— a rule Terraform doesn't know about, that it would remove on `apply`.

This is intentional: CI-scheduled (or PR-triggered) `terraform plan` is a
genuine detective control, catching drift on a schedule instead of by
accident. A production version of this pattern would typically run `plan`
on a cron schedule too (not just on PR), specifically to catch drift from
sources that don't go through a PR at all — like an emergency break-glass
session run directly against production.

## The remediation decision — not a lookup, a judgment call

When `terraform plan` shows this kind of drift, there are two legitimate
responses:

1. **`terraform apply`** — forces reality back to declared state (removes
   the out-of-band rule). Correct if the incident is resolved and the rule
   is genuinely stale.
2. **Run `ansible/playbooks/break-glass-disable.yml`** — removes the rule
   the same way it was added, preserving the audit-trail semantics of an
   explicit, attributable "break-glass access was closed" event rather
   than having Terraform silently absorb the cleanup.

**Diagnosing drift and correctly remediating it are different skills.**
`terraform plan`'s output alone can't tell you *why* the drift exists or
whether it's safe to revert — that requires checking the rule's own
description field (which embeds the incident ticket ID and timestamp,
by design) and confirming whether that incident is actually closed.
Blindly running `apply` to "fix" drift without that context risks
revoking access someone still needs mid-incident.

## Try it yourself

```bash
# 1. Provision (see README.md for full setup — AWS credentials required)
cd terraform/environments/dev
terraform apply

# 2. Inject the drift — a real, temporary SSH rule via Ansible
cd ../../../ansible
INCIDENT_TICKET=DEMO-001 ansible-playbook -i inventory.aws_ec2.yml playbooks/break-glass-enable.yml

# 3. Observe the drift
cd ../terraform/environments/dev
terraform plan
# Note the unplanned security group change

# 4a. Remediate via Terraform...
terraform apply

# 4b. ...OR remediate via Ansible (pick one, not both)
cd ../../../ansible
INCIDENT_TICKET=DEMO-001 ansible-playbook -i inventory.aws_ec2.yml playbooks/break-glass-disable.yml
```
