# A sample secret, so there is something for the "devops-lab-read" policy (policy.tf) and
# the Jenkins demo pipeline (jenkins/casc/jenkins.yaml) to read.

resource "vault_kv_secret_v2" "devops_lab" {
  mount = vault_mount.kv.path
  name  = "devops-lab"

  data_json = jsonencode({
    greeting = "hello from vault-tf"
  })
}
