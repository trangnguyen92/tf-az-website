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
        │  VNet (10.0.0.0/16)│                             │
        │  ┌─────────────────▼──────────┐                  │
        │  │ client-subnet (10.0.1.0/24)│                  │
        │  │  Windows Server 2022 VM    │                  │
        │  │  (RDP jump box)            │                  │
        │  └─────────────┬───────────────┘                 │
        │                │ TCP 80, 22 (client subnet only) │
        │  ┌─────────────▼───────────────┐                 │
        │  │ server-subnet (10.0.2.0/24) │                 │
        │  │  Ubuntu 22.04 VM, no public IP│               │
        │  │  nginx → "Hello World"      │                 │
        │  └─────────────┬───────────────┘                 │
        │                │ outbound only (apt install)     │
        │        ┌───────▼────────┐                        │
        │        │  NAT Gateway   │────────► Internet       │
        │        └────────────────┘   (outbound only)      │
        └───────────────────────────────────────────────────┘
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
   ```

   **Blast radius warning:** this Service Principal holds the `Contributor`
   role scoped to the **entire subscription**, so the long-lived secret stored
   in GitHub Actions can create or modify anything in the subscription —
   including the Terraform state storage account that backs this project.
   That is acceptable for a solo demo repo, but it must be narrowed (e.g.
   scoped to just `tf-az-webserver-rg` and `tf-az-webserver-state-rg`) before
   adding collaborators or accepting PR-based `terraform plan` runs from
   untrusted contributors.

## Deploying

- Open a PR against `main` → `terraform-ci.yml` runs `fmt`, `validate`, and
  `plan`. It triggers on *every* pull request, regardless of which files
  changed.
- Merge to `main` → `terraform-apply.yml` applies automatically. Unlike CI,
  apply is filtered by path: it only runs when a `.tf` file, something under
  `cloud-init/`, or the apply workflow itself changed, so docs-only pushes
  don't trigger a billable apply.
- Changed only a secret (e.g. `OPERATOR_IPS` after your IP changed) with no
  matching file change? Trigger `terraform-apply.yml` manually instead of a
  throwaway commit: Actions tab → "Terraform Apply" → "Run workflow".
- Run the `Terraform Destroy` workflow manually (Actions tab →
  "Terraform Destroy" → "Run workflow") to tear everything down
  between sessions and control cost.

## Demo: proving client-only access

```bash
CLIENT_IP=$(terraform output -raw client_public_ip)
SERVER_IP=$(terraform output -raw server_private_ip)
```

1. RDP into `$CLIENT_IP` using the admin username/password from your
   `terraform.tfvars`. Server Core has no desktop/taskbar — the RDP session
   lands directly in a console window (`cmd.exe`); type `powershell` there
   if you want a PowerShell prompt instead.
2. In that console (or PowerShell) session on the client VM:
   ```
   curl.exe http://<server-private-ip>
   ```
   → returns the "Hello World" page. Proves client → server access.
3. From your own local machine (not the client VM):
   ```bash
   curl http://$SERVER_IP --max-time 5
   ```
   → times out. The server's private IP has no route from outside the
   VNet — this isn't a firewall rule that could be misconfigured, it's
   architecturally unreachable.

## Trade-offs

| Decision | Chosen | Alternative | Why |
|---|---|---|---|
| GitHub Actions auth | Service Principal + secret | OIDC federated credentials | Faster to set up; OIDC is the safer follow-up (no long-lived secret). The SP is `Contributor` over the whole subscription — see the blast-radius warning in [One-time setup](#one-time-setup). |
| Apply gating | Auto-apply on merge to `main` | Required manual approval | Speed over safety for a demo project. |
| Server outbound internet | NAT Gateway | Pre-baked VM image (Packer) | Simpler in Terraform directly; a pre-baked image avoids the NAT Gateway's small running cost. |
| "Windows client" OS | Windows Server 2022 Datacenter, **Server Core** (no GUI) | Windows Server 2022 Desktop Experience | Desktop Experience needs 2 GiB RAM minimum (Microsoft's own figure) but free-tier `B1s` only has 1 GiB — the GUI shell alone starved new processes of memory (`0xc0000142` crash on PowerShell launch, observed in practice). Server Core has no GUI shell, fits comfortably in 1 GiB, and still ships `curl.exe`/PowerShell/cmd. |
| Terraform layout | Flat root-level files | Reusable modules | Faster at this project's size; module extraction is a reasonable future step. |

## Known issues

**VM Agent Platform Updates Drift:** Azure's `vm_agent_platform_updates_enabled`
argument is a provider-computed field on both VM resources (not explicitly set
in `server.tf` or `client.tf`) and drifts between Azure's actual state and
Terraform's default on every plan/apply. This causes `terraform plan` in CI to
report a stable, non-destructive "2 to change" instead of a literal "No changes"
on every run. This is expected and harmless — no resources are destroyed or
recreated. A future cleanup could pin this argument explicitly in both VM
resources to eliminate the noise and achieve truly stable plans.

## Cost notes

- Both VMs are `Standard_B1s` — covered by the Azure free account's
  12-month free VM hours allowance.
- The NAT Gateway + its public IP are **not** free-tier eligible
  (minor hourly + per-GB cost) — run the `Terraform Destroy` workflow
  between sessions to avoid leaving it running.
- The state storage account's cost is negligible at this scale.
