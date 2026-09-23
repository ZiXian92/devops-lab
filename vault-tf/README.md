# vault-tf

Terraform root module that manages the **internal resources of Vault** (secrets engines,
policies, auth methods) using the
[`hashicorp/vault`](https://registry.terraform.io/providers/hashicorp/vault) provider.

> **Run this only after the Vault container is up and unsealed.** Vault itself is started by
> `scripts/Start-Services.ps1` (VS Code task **Compose: up + post-startup**), which also
> initializes it on first run (`vault operator init`, single key share -- lab only), unseals
> it, and writes this module's variable values (`vault_addr`, `vault_token`) to the
> gitignored `terraform.auto.tfvars.json` in this folder. Terraform loads that file
> automatically. It is the only source of variable values -- `variables.tf` has no
> defaults -- so edit values there (or re-run the script), not anywhere else.
>
> The unseal key and root token are saved to `vault/secrets/init.json` (gitignored, repo
> root). Back it up for anything beyond this lab; losing it with no other key share means
> the data in Vault is unrecoverable.

## Apply

Normally you don't run this by hand: the VS Code task **Terraform: apply all**
(`scripts/Apply-Terraform.ps1`) applies every `*-tf` module, and **Compose: up +
post-startup** runs it as its last step. Because Jenkins reads Vault credentials from JCasC
only at startup, `Start-Services.ps1` also restarts the `jenkins` container after Terraform
apply if this module wrote a new AppRole credential (see below).

To run just this module manually: Terraform runs in its official container (house rule --
see `docs/architecture.md`). From the repo root, in PowerShell:

```powershell
$tf = 'docker.io/hashicorp/terraform:1.16'
podman run --rm -v "${PWD}\vault-tf:/work" -w /work $tf init
podman run --rm -v "${PWD}\vault-tf:/work" -w /work $tf apply
```

The container reaches Vault through `http://host.containers.internal:8200`
(the `vault_addr` value), since `localhost` inside the container is the container itself.

## What's here

| File | What it manages |
|---|---|
| `main.tf` | `secret`: a KV v2 secrets engine |
| `secret.tf` | `secret/devops-lab`: a sample secret (`greeting`) |
| `policy.tf` | `devops-lab-read`: read-only access to that one secret |
| `approle.tf` | The `approle` auth method, role `jenkins-devops-lab` (carries `devops-lab-read`), and its role-id/secret-id, written to `jenkins-credentials/` |

### Using the AppRole credential

`apply` writes `jenkins-credentials/role-id` and `jenkins-credentials/secret-id`
(gitignored, mode 0600). `docker-compose.yaml` bind-mounts that directory read-only into the
`jenkins` container at `/run/vault-credentials`. The `jobs:` script in
`jenkins/casc/jenkins.yaml` reads both files and adds a `vault-approle` credential (a
`hashicorp-vault-plugin` AppRole credential) to the **`vault-demo` folder's own credential
store**, not the global one -- so only jobs inside that folder (currently just
`vault-demo/vault-secret-demo`, defined in the same script) can use it. That pipeline job
uses it to read `secret/devops-lab` and print it.

Because this script only runs when Jenkins starts, restart the controller after the first
real apply (and after any `-replace` rotation) so it picks up the new secret-id:

```powershell
podman compose restart jenkins
```

The secret-id has no expiry configured here (lab default); rotate it with
`apply -replace='vault_approle_auth_backend_role_secret_id.jenkins'` followed by the restart
above.
