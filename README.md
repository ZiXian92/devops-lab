# devops-lab

A local DevOps lab on a single Windows machine. It runs a private **Nexus** registry under Podman, manages Nexus's internal configuration with **Terraform**, and provides a small library of **Helm chart templates** that are linted, tested and published to that registry. Everything is driven by VS Code tasks (`Terminal > Run Task...`), which wrap the PowerShell scripts in [scripts/](scripts/).

## What's in the repo

| Path | Purpose |
|---|---|
| [docker-compose.yaml](docker-compose.yaml) | The services: Nexus, and `helm-cicd`, a tool container with helm, helm-unittest and kubeconform |
| [scripts/](scripts/) | PowerShell entry points behind the VS Code tasks |
| [nexus-tf/](nexus-tf/) | Terraform for Nexus's internal resources: repositories, roles, users. See its [README](nexus-tf/README.md) |
| [app-deployment-template-charts/](app-deployment-template-charts/) | Helm charts, one directory per chart |
| [images/helm-cicd/](images/helm-cicd/) | Dockerfile and `tasks.sh` for the `helm-cicd` container |
| [.vscode/tasks.json](.vscode/tasks.json) | The task definitions |

## Prerequisites

- Windows with PowerShell 5.1+ and VS Code
- Podman, with a running machine (`podman machine start`) and a compose provider (`docker-compose` or `podman-compose`) on `PATH`

Terraform and Helm need no local install. They run in containers.

## Initial setup

1. In VS Code, run the task **Compose: first-time setup (set Nexus admin password)**.
2. Enter the Nexus admin password you want when prompted.

The task starts the services and then configures Nexus:

- changes the admin password from Nexus's generated initial one to yours
- accepts the license agreement
- disables anonymous access
- saves the admin credentials to `nexus-tf/terraform.auto.tfvars.json` (gitignored)
- runs `terraform apply` to create the OCI registry, the Helm users and their credential files

Nexus is then available at <http://localhost:8081> (user `admin`). The first start takes a few minutes.

After that, use **Compose: up + post-startup** to bring the lab back up. It reuses the saved password and never prompts. It is safe to re-run.

## Making infra changes

"Infra" here means the internal configuration of the services (Nexus repositories, roles, users, and so on), which is defined as Terraform in `*-tf/` modules.

1. Edit the `.tf` files in the module, for example [nexus-tf/](nexus-tf/).
2. Run the task **Terraform: apply all**.

The task runs `terraform init` and `apply -auto-approve` for every top-level `*-tf` directory, in a container. It is idempotent, so with no changes it does nothing. It needs the services to be running. **Compose: up + post-startup** also runs it as its last step.

Variable values live in `nexus-tf/terraform.auto.tfvars.json`, which the setup task writes. Terraform state is local, in the module directory. Don't delete it.

To add another system:

1. Add its service to `docker-compose.yaml`.
2. Write an `Initialize-<Service>` function in [scripts/Start-Services.ps1](scripts/Start-Services.ps1), and call it before the Terraform step.
3. Create a `<system>-tf/` directory. `Apply-Terraform.ps1` picks it up automatically.

## Helm charts

Charts live in `app-deployment-template-charts/<chart>/`. [web-app](app-deployment-template-charts/web-app/) is the reference chart:

```
web-app/
  Chart.yaml
  values.yaml
  values.schema.json     validates values
  templates/
  tests/*_test.yaml      helm-unittest suites
  tests/values/*.yaml    extra value sets rendered by the manifest validation
```

### Develop

Edit the chart in your editor. There is no local Helm install to maintain, because the tests run in the `helm-cicd` container, which mounts the charts read-only.

Keep `values.schema.json` and the tests in step with `values.yaml` when you add or change a value.

To add a new chart, create a new directory with a `Chart.yaml`. Then add its directory name to the `chart` and `publishChart` option lists in the `inputs` section of [.vscode/tasks.json](.vscode/tasks.json), because VS Code cannot list directories dynamically.

### Test

Run the task **Helm: test chart(s)** and pick a chart, or pick `all` to test every chart in turn. Each chart gets:

1. `helm lint --strict`
2. the helm-unittest suites in `tests/`
3. kubeconform on the rendered manifests, for the default values and each `tests/values/*.yaml`

With `all`, a failing chart doesn't stop the run. A pass/fail summary is printed at the end.

### Publish

Run the task **Helm: publish chart to Nexus**, then pick a chart and enter a semantic version, for example `1.2.0` or `1.3.0-rc.1`.

The task:

1. sets `version:` in the chart's `Chart.yaml`
2. runs the full tests
3. packages the chart and pushes it to `oci://localhost:8081/oci-internal/helm/deployment-templates/<chart>` as the `helm-publisher` user

If the tests or the push fail, `Chart.yaml` is restored. On success it keeps the published version, so commit it. Charts are published one at a time, because each has its own version cadence.

Pull a published chart with the read-only `helm-puller` credentials (Nexus is plain HTTP):

```powershell
helm pull oci://localhost:8081/oci-internal/helm/deployment-templates/web-app --version 1.2.0 `
  --registry-config nexus-tf\helm-registry\puller.json --plain-http
```

## Changing the helm-cicd image

After editing `images/helm-cicd/`, rebuild it with `podman compose up -d --build helm-cicd`. Or run `scripts/Test-Charts.ps1` or `scripts/Publish-Chart.ps1` with `-Rebuild`.
