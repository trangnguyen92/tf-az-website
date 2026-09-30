# main.auto.tfvars
# Non-secret configuration, auto-loaded by Terraform on every run (local and CI).
# Kept in version control so local applies and GitHub Actions applies target the
# same region and resource group instead of silently relying on variables.tf
# defaults. Secrets stay in the gitignored terraform.tfvars / CI secrets.

location            = "swedencentral"
resource_group_name = "tf-az-webserver-rg"
