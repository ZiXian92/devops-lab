# nexus-tf

Terraform root module that manages the **internal resources of Nexus**
(repositories, blob stores, roles, users, ...) using the
[`datadrivers/nexus`](https://registry.terraform.io/providers/datadrivers/nexus) provider.

> **Run this only after the Nexus container is up.** Nexus itself is started by
> `scripts/Start-Services.ps1` (VS Code task **Compose: up + post-startup**), which also
> sets the admin password (on the first run, use the task **Compose: first-time setup (set
> Nexus admin password)**, which asks for it; once this folder's `terraform.auto.tfvars.json`
> exists the plain task reuses it without asking) and writes all of this module's variable values
> (`nexus_url`, `nexus_admin_username`, `nexus_admin_password`) to the gitignored
> `terraform.auto.tfvars.json` in this folder. Terraform loads that file
> automatically. It is the only source of variable values -- `variables.tf` has no
> defaults -- so edit values there (or re-run the script), not anywhere else.

## Apply

Normally you don't run this by hand: the VS Code task **Terraform: apply all**
(`scripts/Apply-Terraform.ps1`) applies every `*-tf` module, and **Compose: up +
post-startup** runs it as its last step.

To run just this module manually: Terraform runs in its official container (house rule --
see `docs/architecture.md`). From the repo root, in PowerShell:

```powershell
$tf = 'docker.io/hashicorp/terraform:1.16'
podman run --rm -v "${PWD}\nexus-tf:/work" -w /work $tf init
podman run --rm -v "${PWD}\nexus-tf:/work" -w /work $tf apply
```

The container reaches Nexus through `http://host.containers.internal:8081`
(the `nexus_url` value), since `localhost` inside the container is the container itself.

## OCI registry for images and Helm charts

| File | What it manages |
|---|---|
| `oci-repository.tf` | `oci-internal`: a native OCI-format hosted repo (images, Helm charts, ...; created via the `restapi` provider because the nexus provider has no OCI resource) with **path-based routing** (no extra port), plus the **OCI Bearer Token** realm |
| `helm-access.tf` | Content selector limited to `/helm/deployment-templates`, one privilege + role + user each for **helm-publisher** (browse/read/add/edit) and **helm-puller** (browse/read), and their credential files |


### Using the credentials

`apply` writes a docker-style auth file per account to `nexus-tf/helm-registry/`
(`publisher.json`, `puller.json`; gitignored, mode 0600). Point helm at one:

```powershell
helm push chart-1.0.0.tgz oci://localhost:8081/oci-internal/helm/deployment-templates --registry-config nexus-tf\helm-registry\publisher.json --plain-http
helm pull oci://localhost:8081/oci-internal/helm/deployment-templates/chart --version 1.0.0 --registry-config nexus-tf\helm-registry\puller.json --plain-http
```

(`$env:HELM_REGISTRY_CONFIG` works in place of `--registry-config`.) Passwords are random,
kept in the local state, and rotated with
`apply -replace='random_password.helm["publisher"]'`.
