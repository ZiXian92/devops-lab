# OCI registry for container images AND Helm charts (helm push oci://... stores charts as
# OCI artifacts). Uses Nexus's native "oci" repository format (3.94+), not the older
# Docker format.
#
# The datadrivers/nexus provider has no OCI resources yet, so the repository is created
# through Nexus's REST API with the generic restapi provider. When the datadrivers provider
# gains a nexus_repository_oci_hosted resource, move to it (destroy + recreate; the repo
# name is the identity, so do it while the repo is still empty).

locals {
  # OCI repository names must be lowercase.
  oci_repo_name = "oci-internal"

  # Path-based routing: no per-repo connector port. Clients use Nexus's main port and put
  # the repository name first in the image path: <host>/<repo>/<image>[:tag],
  # e.g. localhost:8081/oci-internal/helm/deployment-templates/<chart>.
  # Use this setting for every OCI repo so they all share one host:port (and one
  # reverse-proxy "/" rule if TLS on 443 is put in front later).
  oci_registry_host = "localhost:8081"
}

resource "restapi_object" "oci_hosted" {
  # POST creates; GET/PUT use .../oci/hosted/<name>; DELETE is format-agnostic.
  path         = "/service/rest/v1/repositories/oci/hosted"
  destroy_path = "/service/rest/v1/repositories/{id}"
  id_attribute = "name"

  # Nexus returns extra fields (url, format, type, cleanup, ...); only drift in what is set
  # below counts.
  ignore_server_additions = true

  data = jsonencode({
    name   = local.oci_repo_name
    online = true

    oci = {
      pathEnabled = true # path-based routing (see above)
      # false = clients authenticate via the OCI Bearer Token realm (enabled below).
      forceBasicAuth = false
      v1Enabled      = false
    }

    storage = {
      blobStoreName               = "default"
      strictContentTypeValidation = true
      # Overwrites allowed (mutable tags such as :latest). Switch to "ALLOW_ONCE" to make
      # chart versions immutable; publishers then only need ADD, not EDIT.
      writePolicy = "ALLOW"
    }
  })
}

# OCI Bearer Token Realm: required for docker/helm/oras login when forceBasicAuth = false.
# This resource owns the WHOLE active-realm list, so the default must be restated here.
# (DockerToken is deliberately not listed: it is only for Docker-format repositories.)
resource "nexus_security_realms" "this" {
  active = [
    "NexusAuthenticatingRealm", # local users and roles (the only default active realm)
    "OciBearerToken",           # OCI Bearer Token Realm
  ]
}
