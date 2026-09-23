# AppRole auth method, with one role for Jenkins carrying the "devops-lab-read" policy
# (policy.tf). role-id/secret-id are written to jenkins-credentials/ below and bind-mounted
# straight into the jenkins container as the "vault-approle" credential (JCasC, see
# jenkins/casc/jenkins.yaml) -- the same pattern nexus-tf/helm-access.tf uses for Nexus
# credentials, since this container only ever sees this module's own directory.
#
# NOT ephemeral, on purpose: hashicorp/local has no write-only argument on
# local_sensitive_file (see nexus-tf/helm-access.tf), so the secret_id can't be written to a
# file that way. It is therefore a regular vault_approle_auth_backend_role_secret_id,
# sensitive, held only in the gitignored local state. Rotate it with
#   terraform apply -replace=vault_approle_auth_backend_role_secret_id.jenkins

resource "vault_auth_backend" "approle" {
  type = "approle"
  path = "approle"
}

resource "vault_approle_auth_backend_role" "jenkins" {
  backend        = vault_auth_backend.approle.path
  role_name      = "jenkins-devops-lab"
  token_policies = [vault_policy.devops_lab_read.name]
  token_ttl      = 3600
  token_max_ttl  = 7200
}

data "vault_approle_auth_backend_role_id" "jenkins" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.jenkins.role_name
}

resource "vault_approle_auth_backend_role_secret_id" "jenkins" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.jenkins.role_name
}

resource "local_sensitive_file" "jenkins_credentials" {
  for_each = {
    "role-id"   = data.vault_approle_auth_backend_role_id.jenkins.role_id
    "secret-id" = vault_approle_auth_backend_role_secret_id.jenkins.secret_id
  }

  filename        = "${path.module}/jenkins-credentials/${each.key}"
  content         = each.value
  file_permission = "0600"
}
