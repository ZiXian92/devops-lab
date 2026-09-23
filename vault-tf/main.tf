# Internal Vault resources (secrets engines, policies, auth methods) go here. Vault itself
# is started and unsealed by scripts/Start-Services.ps1; this module only manages what
# lives INSIDE a running, unsealed Vault.

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "devops-lab KV v2 secrets engine"
}
