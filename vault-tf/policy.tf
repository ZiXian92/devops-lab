# Default policy: read-only access to the one secret this module deposits (secret.tf). KV v2
# reads go through the mount's "data/" subpath.

resource "vault_policy" "devops_lab_read" {
  name = "devops-lab-read"

  policy = <<-EOT
    path "${vault_mount.kv.path}/data/${vault_kv_secret_v2.devops_lab.name}" {
      capabilities = ["read"]
    }
  EOT
}
