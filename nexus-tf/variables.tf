# No defaults on purpose: every value comes from terraform.auto.tfvars.json, which is
# written by scripts/Start-Services.ps1 (gitignored). One source, so nothing can
# silently override or be overridden by a default here.

variable "nexus_url" {
  description = "Base URL of the Nexus instance. Terraform runs in a container, so this must reach the host-published port 8081 via podman's host alias (http://host.containers.internal:8081) rather than localhost."
  type        = string
}

variable "nexus_admin_username" {
  description = "Nexus admin user."
  type        = string
}

variable "nexus_admin_password" {
  description = "Nexus admin password."
  type        = string
  sensitive   = true
}
