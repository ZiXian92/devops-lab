# Helm publisher / puller accounts, restricted with a content selector to one path prefix
# of the OCI repo. Generated passwords are written to local sensitive files that
# `helm --registry-config` reads.
#
# NOT ephemeral, on purpose: hashicorp/local (2.9.1) has no write-only argument on
# local_sensitive_file, so an ephemeral password cannot be written to a file. (The only
# ephemeral local resource, local_command, re-runs every plan/apply and would hand the file a
# new password that Nexus never received.) The password is therefore a regular
# random_password: sensitive, held only in the gitignored local state. Rotate one with
#   terraform apply -replace='random_password.helm["publisher"]'

locals {
  # Image/chart name prefix everything for helm lives under: oci://<host>/helm/deployment-templates/<chart>
  helm_path_prefix = "helm/deployment-templates"

  helm_accounts = {
    publisher = {
      userid    = "helm-publisher"
      firstname = "Helm"
      lastname  = "Publisher"
      # push needs the read actions too (HEAD/GET to skip existing blobs); EDIT is for
      # overwriting an existing tag while write_policy is ALLOW.
      actions = ["BROWSE", "READ", "ADD", "EDIT"]
    }
    puller = {
      userid    = "helm-puller"
      firstname = "Helm"
      lastname  = "Puller"
      actions   = ["BROWSE", "READ"]
    }
  }
}

# --- Content selector: only the helm/deployment-templates subtree ---------------------------
# Asset paths in an OCI repo are "/v2/<image name>/manifests/<ref>" and
# "/v2/<image name>/blobs/<digest>", hence the /v2 in front of the prefix. The repository name
# is NOT part of the path (verified with helm push/pull under path-based routing).
resource "nexus_security_content_selector" "helm_deployment_templates" {
  name        = "helm-deployment-templates"
  description = "OCI assets under /${local.helm_path_prefix}"
  expression  = "format == \"oci\" and path =^ \"/v2/${local.helm_path_prefix}/\""
}

# --- Privileges, roles, users (one of each per account) ------------------------------------
resource "nexus_privilege_repository_content_selector" "helm" {
  for_each = local.helm_accounts

  name             = "helm-deployment-templates-${each.key}"
  description      = "${title(each.key)} access to /${local.helm_path_prefix} in ${local.oci_repo_name}"
  format           = "oci"
  repository       = restapi_object.oci_hosted.id
  content_selector = nexus_security_content_selector.helm_deployment_templates.name
  actions          = each.value.actions
}

resource "nexus_security_role" "helm" {
  for_each = local.helm_accounts

  roleid      = "helm-deployment-templates-${each.key}"
  name        = "helm-deployment-templates-${each.key}"
  description = "${title(each.key)} for /${local.helm_path_prefix} in ${local.oci_repo_name}"
  privileges  = [nexus_privilege_repository_content_selector.helm[each.key].name]
}

resource "random_password" "helm" {
  for_each = local.helm_accounts

  length  = 32
  special = false
}

resource "nexus_security_user" "helm" {
  for_each = local.helm_accounts

  userid    = each.value.userid
  firstname = each.value.firstname
  lastname  = each.value.lastname
  email     = "${each.value.userid}@example.invalid"
  status    = "active"
  roles     = [nexus_security_role.helm[each.key].roleid]

  password = random_password.helm[each.key].result
}

# --- Credential files for helm ---------------------------------------------------------------
# Docker-style auth file, the format helm's registry client reads. One file per account so
# each is used explicitly:
#   helm push chart.tgz oci://localhost:8081/oci-internal/helm/deployment-templates \
#     --registry-config nexus-tf/helm-registry/publisher.json --plain-http
# (or set HELM_REGISTRY_CONFIG). Kept inside this module, gitignored, because Terraform
# runs in a container that only sees this directory.
resource "local_sensitive_file" "helm_registry_config" {
  for_each = local.helm_accounts

  filename = "${path.module}/helm-registry/${each.key}.json"

  content = jsonencode({
    auths = {
      (local.oci_registry_host) = {
        auth = base64encode("${each.value.userid}:${random_password.helm[each.key].result}")
      }
    }
  })

  # Only the owner may read the file.
  file_permission = "0600"
}
