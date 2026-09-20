provider "nexus" {
  url      = var.nexus_url
  username = var.nexus_admin_username
  password = var.nexus_admin_password
}

# For Nexus endpoints the nexus provider has no resource for (native OCI repositories).
provider "restapi" {
  uri      = var.nexus_url
  username = var.nexus_admin_username
  password = var.nexus_admin_password

  headers = {
    "Content-Type" = "application/json"
  }

  # Nexus answers create/update with an empty body; the provider then re-reads the object.
  write_returns_object = false
}
