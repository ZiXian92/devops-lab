# Single-node, non-dev Vault server. File storage persists in the vault-data volume
# (docker-compose.yaml), but Vault still starts sealed on every restart; Start-Services.ps1
# unseals it. Plain HTTP, matching Nexus's lab setup -- not for anything beyond this lab.

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# No IPC_LOCK capability is granted to the container (see docker-compose.yaml); mlock would
# fail without it.
disable_mlock = true

ui = true
