# No defaults on purpose: every value comes from terraform.auto.tfvars.json, which is
# written by scripts/Start-Services.ps1 (gitignored). One source, so nothing can
# silently override or be overridden by a default here.

variable "vault_addr" {
  description = "Base URL of the Vault instance. Terraform runs in a container, so this must reach the host-published port 8200 via podman's host alias (http://host.containers.internal:8200) rather than localhost."
  type        = string
}

variable "vault_token" {
  description = "Vault root token (from vault operator init, saved by Start-Services.ps1 to vault/secrets/init.json)."
  type        = string
  sensitive   = true
}
