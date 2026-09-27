# Infrastructure Drift Detection — Architecture & Operations Guide

> **Target Audience:** Junior to Senior Software & DevOps Engineers
> **Workflows:** [`.github/workflows/drift-detector.yml`](../.github/workflows/drift-detector.yml) | [`.github/workflows/inject-drift.yml`](../.github/workflows/inject-drift.yml)
> **Environment:** `terraform/environments/dev` & `ansible/playbooks/`

---

## 1. What "Drift" Means in This Lab

In Infrastructure as Code (IaC), **drift** occurs when real-world cloud resources diverge from the configuration declared in source control.

In this repository:
* **The Declared State (Terraform):** `terraform/environments/dev` defines an EC2 instance and a security group with **zero inbound rules** (`terraform/modules/ssm-instance/main.tf`). Access is exclusively via AWS Systems Manager (SSM) Session Manager — no SSH key, no open port 22, by design.
* **The Legitimate Incident Tool (Ansible):** [`ansible/playbooks/break-glass-enable.yml`](../ansible/playbooks/break-glass-enable.yml) is a break-glass incident-response tool. When SSM itself is unreachable during an emergency, this playbook opens a scoped, temporary SSH ingress rule (single IP CIDR, never `0.0.0.0/0`), pushes an ephemeral 60-second public key via EC2 Instance Connect, and schedules auto-revocation via `at`.
* **The Drift Scenario:** That playbook modifies the AWS Security Group **directly via the AWS EC2 API** — completely outside Terraform. Terraform's state file (`terraform.tfstate` in S3) has no record of this change.

If the self-scheduled auto-revoke doesn't fire (the `at` daemon isn't running, the task ran on a disposable CI runner VM, or the engineer forgot manual cleanup), the rule persists indefinitely: **reality has diverged from declared state, and nothing will notice unless automated detective controls are actively looking.**

```
    +-------------------------+               +-------------------------+
    |   Declared State (Git)  |               |  Real World (Live AWS)  |
    |   EC2 Security Group:   |  DIVERGENCE   |   EC2 Security Group:   |
    |   0 Inbound Rules       | <===========> |   Port 22 OPEN (SSH)    |
    |   (SSM Session only)    |    (DRIFT)    |   (Added via Ansible)   |
    +-------------------------+               +-------------------------+
```

---

## 2. System Architecture & Zero-Secret OIDC

The drift detection mechanism runs in GitHub Actions using **AWS OpenID Connect (OIDC)** federated identity — no permanent AWS access keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) are ever stored in GitHub.

```mermaid
flowchart TD
    subgraph GitHubActions["GitHub Actions Runner (Ubuntu)"]
        Trigger["Trigger: Cron (Every 6h) or Manual Dispatch"]
        OIDC["OIDC Token Request (jwt)"]
        SetupTF["Install Terraform CLI (wrapper: false)"]
        Init["terraform init (Fetch S3 State)"]
        Plan["terraform plan -detailed-exitcode"]
        Summary["Generate GitHub Step Summary"]
    end

    subgraph AWS["Amazon Web Services (AWS)"]
        IAM["IAM OIDC Provider + Plan Role (ReadOnly)"]
        S3State[("S3 State Bucket (terraform.tfstate)")]
        LiveEC2["Live EC2 & Security Group API"]
    end

    Trigger --> OIDC
    OIDC -->|AssumeRoleWithWebIdentity| IAM
    IAM -->|Temporary STS Credentials| GitHubActions
    SetupTF --> Init
    Init -->|Read State| S3State
    Plan -->|DescribeSecurityGroups / DescribeInstances| LiveEC2
    Plan -->|Compare Code vs State vs AWS| Summary
```

### Least Privilege IAM Boundary

1. **`PLAN_ROLE_ARN` (Read-Only Detective Control):**
   * The scheduled drift detector assumes `PLAN_ROLE_ARN`.
   * It only has permissions to describe resources (`ec2:Describe*`, `s3:GetObject`).
   * Even if an attacker compromises the workflow runner, the drift detector **cannot alter or destroy cloud resources**.
2. **`APPLY_ROLE_ARN` (Mutating Control):**
   * Only assumed by gated workflows running in the `production` GitHub Environment.
   * Used exclusively by `apply.yml` and `inject-drift.yml`.

---

## 3. The Detection Engine: How It Works Under the Hood

The detective control relies on Terraform's **`-detailed-exitcode`** flag.

### Standard vs Detailed Exit Codes

Normally, `terraform plan` exits with `0` as long as it executes without crashing. With `-detailed-exitcode`, Terraform signals differences between live infrastructure and declared code:

| Exit Code | Meaning | Detective Control Action | Result |
| :---: | :--- | :--- | :---: |
| **`0`** | **In Sync:** Live AWS matches Terraform code. Plan diff is completely empty. | Emits green confirmation in `$GITHUB_STEP_SUMMARY`. | ✅ Passed |
| **`1`** | **Execution Error:** Syntax error, AWS rate limit, network failure, or invalid IAM permissions. | Emits red failure banner; terminates workflow. | ❌ Error |
| **`2`** | **Drift Detected:** Terraform succeeded, but found changes! Live infrastructure diverged. | Captures diff into summary, alerts team, and fails job (`exit 2`). | ⚠️ Drift Found |

```mermaid
flowchart TD
    Start(["Start Drift Detector Workflow"]) --> Init["terraform init -backend-config=..."]
    Init --> PlanCmd["terraform plan -detailed-exitcode -no-color -out=tfplan"]
    PlanCmd --> CheckCode{"Check Exit Code ($?)"}

    CheckCode -->|Exit Code = 0| InSync["No Changes: Cloud matches Git<br/>Render Green Step Summary"]
    InSync --> Success([Workflow Succeeded])

    CheckCode -->|Exit Code = 2| Drift["Changes Detected: Cloud diverged!<br/>Format Diff into Collapsible Details<br/>Print Remediation Guide"]
    Drift --> FailJob["Fail Workflow (exit 2)<br/>Notify Repo Owner / On-Call"]

    CheckCode -->|Exit Code = 1 or Other| Failure["CLI or Authentication Error<br/>Render Error Log"]
    Failure --> ErrorJob["Fail Workflow (exit 1)"]
```

> [!IMPORTANT]
> **Why `terraform_wrapper: false` is required:**
> By default, GitHub's `hashicorp/setup-terraform` action wraps the `terraform` CLI in a Node.js wrapper script. This wrapper intercepts stdout and normalizes non-zero exit codes to `0` or `1`, masking exit code `2`. Setting `terraform_wrapper: false` ensures the true exit code `2` passes directly to our evaluation script.

---

## 4. End-to-End Incident Lifecycle

Here is how an emergency break-glass event creates drift, how CI catches it, and how an engineer resolves it:

```mermaid
sequenceDiagram
    autonumber
    actor Engineer as On-Call Engineer
    participant Ansible as Ansible Playbook
    participant AWS as Live AWS (Security Group)
    participant TF as Terraform State (S3)
    participant Cron as Drift Detector (Cron / Manual)
    participant UI as GitHub Actions Summary

    Note over Engineer,AWS: Emergency Incident (SSM is unreachable)
    Engineer->>Ansible: Run break-glass-enable.yml (INCIDENT_TICKET=DEMO-001)
    Ansible->>AWS: Authorize port 22 for 203.0.113.42/32 (Out-of-band API call)
    Note over AWS,TF: Drift exists! AWS has port 22 open, but TF state has 0 rules.

    Note over Cron,UI: Scheduled Cron Triggers (Every 6h)
    Cron->>TF: terraform init (Pull declared state)
    Cron->>AWS: terraform plan (Inspect live security group)
    AWS-->>Cron: Returns live rules (Port 22 detected!)
    Cron->>Cron: Plan detects 1 unplanned addition (Exit Code = 2)
    Cron->>UI: Post detailed diff & remediation options to Summary
    Cron-->>Engineer: Red Workflow Alert: "Infrastructure Drift Detected"

    Note over Engineer,AWS: Remediation Decision
    alt Option A: Incident Still Active
        Engineer->>Engineer: Verify ticket DEMO-001 is active. Keep temporary rule until resolved.
    else Option B: Incident Resolved (Ansible Remediation)
        Engineer->>Ansible: Run break-glass-disable.yml
        Ansible->>AWS: Revoke port 22 rule
        Engineer->>Cron: Re-run Drift Detector -> Passes with Exit Code 0!
    else Option C: Reconcile via Terraform
        Engineer->>AWS: Run Lab infrastructure (apply) -> Overwrites AWS back to code
    end
```

---

## 5. The Remediation Playbook (Junior Engineer Checklist)

Diagnosing drift and remediating it are two distinct steps. **Never blindly run `apply` to eliminate drift without investigation.**

Follow this triage decision tree:

```mermaid
flowchart TD
    Alert["Alert: Drift Detected in Dev Security Group"] --> Inspect["Inspect GitHub Step Summary Diff"]
    Inspect --> ReadDesc["Check Rule Description:<br/>'BREAK-GLASS - ticket DEMO-xxx'"]
    ReadDesc --> TicketActive{"Is this Incident Ticket<br/>still open/active?"}

    TicketActive -->|YES| Acknowledge["DO NOT OVERWRITE!<br/>The incident response team is actively using this connection.<br/>Notify incident commander."]
    TicketActive -->|NO / Unknown| RemediateChoice{"Choose Remediation Method"}

    RemediateChoice -->|Method 1: Audit Preservation| RunDisable["Trigger 'Inject drift (TEST)' workflow with action: remediate<br/>(or run ansible break-glass-disable.yml)<br/>Preserves clean audit trail."]
    RemediateChoice -->|Method 2: Force Code Baseline| RunApply["Trigger 'Lab infrastructure' workflow with action: apply<br/>Terraform deletes the unmanaged rule."]

    RunDisable --> Recheck["Run Drift Detector manually -> Verify Status is Green"]
    RunApply --> Recheck
```

### Remediation Tradeoffs

| Remediation Path | How to Execute | When to Use | Audit Trail Impact |
| :--- | :--- | :--- | :--- |
| **Ansible Playbook** (`break-glass-disable.yml`) | Run **Inject drift (TEST)** with `action: remediate`, or run playbook locally | Preferred for known incidents. | **High:** Explicitly attributes the closure of the emergency session in CloudTrail and Ansible logs. |
| **Terraform Apply** | Run **Lab infrastructure** with `action: apply` | Use when drift is from unknown origins (e.g. manual AWS console changes) or incident scripts are unavailable. | **Medium:** Terraform forces live AWS back to declared code, wiping out the unmanaged rule. |

---

## 6. Try It Yourself

You can test this entire lifecycle either completely within **GitHub Actions** or locally using the **CLI**.

### Method A: Via GitHub Actions (Recommended)

1. **Verify Baseline State:**
   * Go to **Actions** → **Drift Detector** → **Run workflow**.
   * The job completes green: `✅ Infrastructure In Sync`.
2. **Inject the Drift:**
   * Go to **Actions** → **Inject drift (TEST)** → **Run workflow** (action: `inject`, ticket: `DEMO-001`).
   * The playbook adds an emergency port 22 rule directly to AWS.
3. **Run the Detector to Observe Drift:**
   * Go to **Actions** → **Drift Detector** → **Run workflow**.
   * The job **fails** with exit code 2. Click into the run summary to see the full `terraform plan` diff showing the unplanned ingress rule.
4. **Remediate:**
   * Go to **Actions** → **Inject drift (TEST)** → **Run workflow** (action: `remediate`).
   * Or go to **Actions** → **Lab infrastructure** → `apply`.
5. **Confirm Clean State:**
   * Re-run **Drift Detector** → passes with exit code 0.

### Method B: Via Local Terminal

```bash
# 1. Ensure live dev environment is applied
cd terraform/environments/dev
terraform apply

# 2. Inject drift via Ansible
cd ../../../ansible
INCIDENT_TICKET=DEMO-001 ansible-playbook -i inventory.aws_ec2.yml playbooks/break-glass-enable.yml

# 3. Observe the drift locally
cd ../terraform/environments/dev
terraform plan
# Notice the unplanned inbound SSH rule!

# 4a. Remediate via Ansible (preserves audit trail)
cd ../../../ansible
INCIDENT_TICKET=DEMO-001 ansible-playbook -i inventory.aws_ec2.yml playbooks/break-glass-disable.yml

# 4b. ...OR remediate via Terraform apply
cd ../terraform/environments/dev
terraform apply
```
