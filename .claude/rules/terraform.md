---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.tfvars.json"
---

# Terraform

- Each system has its own `*-tf/` module. Keep ALL variables in one variables file; no duplicates across *.auto.tfvars.
- Prefer provider-native resources; fall back to restapi only where the provider lacks support (e.g. the OCI repo and its bearer-token realm).
- Credentials: sensitive local file with an ephemeral block; rotate by bumping the write-only version number.
- Repository access: content selectors scoped to path prefixes; separate publish and pull users; path-based routing for all repositories.
- Terraform runs in its container via scripts/Apply-Terraform.ps1, not on the host.
