# tf-az-webserver

Terraform + GitHub Actions project provisioning an Azure VNet with a
public Windows client VM and a network-isolated Ubuntu server VM
serving "Hello World" over nginx.

## Architecture

```
                          Internet
                             │
                    (operator's IP only, RDP 3389)
                             │
                     ┌───────▼────────┐
                     │  Public IP     │
                     └───────┬────────┘
        ┌────────────────────┼────────────────────────────┐
        │  VNet (10.0.0.0/16)│                            │
        │  ┌─────────────────▼──────────┐                 │
        │  │ client-subnet (10.0.1.0/24)│                 │
        │  │  Windows Server 2022 VM    │                 │
        │  │  (RDP jump box)            │                 │
        │  └─────────────┬───────────────┘                │
        │                │ TCP 80, 22 (client subnet only)│
        │  ┌─────────────▼───────────────┐                │
        │  │ server-subnet (10.0.2.0/24) │                │
        │  │  Ubuntu 22.04 VM, no public IP│              │
        │  │  nginx → "Hello World"      │                │
        │  └─────────────┬───────────────┘                │
        │                │ outbound only (apt install)    │
        │        ┌───────▼────────┐                       │
        │        │  NAT Gateway   │────────► Internet     │
        │        └────────────────┘   (outbound only)     │
        └─────────────────────────────────────────────────┘
```

The server has no public IP and its NSG only allows inbound traffic
from the client subnet — it is unreachable from the internet by
network topology, not just firewall rule.

## One-time setup

1. `az login` and select the target subscription.
2. Bootstrap remote state (see `bootstrap/main.tf`):
   ```bash
   cd bootstrap && terraform init && terraform apply
   ```
3. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in
   real values (your IP, an SSH public key, a Windows admin password).
4. Create the CI/CD Service Principal:
   ```bash
   az ad sp create-for-rbac \
     --name "tf-az-webserver-ci" \
     --role Contributor \
     --scopes /subscriptions/$(az account show --query id -o tsv) \
     --sdk-auth
   ```
   This prints JSON containing `clientId`, `clientSecret`, `subscriptionId`,
   and `tenantId`. Set them, plus the non-Azure values, as repo secrets:
   ```bash
   gh secret set ARM_CLIENT_ID --body "<clientId>"
   gh secret set ARM_CLIENT_SECRET --body "<clientSecret>"
   gh secret set ARM_TENANT_ID --body "<tenantId>"
   gh secret set ARM_SUBSCRIPTION_ID --body "<subscriptionId>"
   gh secret set OPERATOR_IPS --body '["<same value(s) as terraform.tfvars operator_ips, e.g. 203.0.113.5/32>"]'
   gh secret set CLIENT_ADMIN_PASSWORD --body "<same value as terraform.tfvars client_admin_password>"
   gh secret set SERVER_SSH_PUBLIC_KEY --body "$(cat ~/.ssh/tf-az-webserver.pub)"
   gh secret set TF_PLAN_PASSPHRASE --body "$(openssl rand -base64 32)"
   ```
   `TF_PLAN_PASSPHRASE` encrypts the saved plan passed from the plan job to
   the approved apply/destroy job (a saved plan holds the sensitive
   variables in plaintext).
5. Create the `deploy-approver` environment with required reviewers
   (Settings → Environments → New environment → `deploy-approver` → Required
   reviewers). The apply and destroy jobs wait for an approval from one of
   these reviewers.

## Deploying

- Open any pull request → `deploy-terraform.yml` runs `fmt`, `validate`, and
  `plan` only (the apply job is skipped). It triggers on *every* pull
  request, regardless of target branch or which files changed.
- Run "Deploy Terraform" manually from a feature branch → `plan` only. Only
  runs on `main` go on to the approval and apply/destroy job.
- Merge to `main` → `deploy-terraform.yml` runs `plan` (review it in the plan
  job's log), then the `apply` job waits for approval on the
  `deploy-approver` environment and applies exactly that saved plan. If the
  state changed in between, Terraform rejects the plan as stale. It is
  filtered by path: it only runs when a `.tf` file, something under
  `cloud-init/`, or the workflow itself changed, so docs-only pushes don't
  trigger a deploy. Editing `cloud-init/server.yaml` replaces the server VM.
- Changed only a secret (e.g. `OPERATOR_IPS` after your IP changed) with no
  matching file change? Run it manually instead of a throwaway commit:
  Actions tab → "Deploy Terraform" → "Run workflow".
- To tear everything down between sessions and control cost, run "Deploy
  Terraform" manually with **destroy** ticked. It runs `plan -destroy`, then
  the `destroy` job waits for approval on `deploy-approver` and executes that
  saved destroy plan.
