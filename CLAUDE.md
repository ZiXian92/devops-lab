# devops-lab

Local lab: Podman + Nexus OSS (plain HTTP) + Terraform + Helm chart templates. Windows 11, PowerShell.

- scripts/: PowerShell entry points, one VS Code task each (.vscode/tasks.json)
- docker-compose.yaml: Nexus and the helm-cicd tool container (images/helm-cicd); run with podman compose
- *-tf/: Terraform per system
- app-deployment-template-charts/: Helm charts

Path-scoped conventions are in .claude/rules/ (helm, terraform, vscode-tasks).

## Working style
- For "how/why/is X true" questions, answer and verify; do not edit files unless asked.
- For non-obvious choices (hardcode vs value, keep vs remove), give a one-line recommendation instead of asking.
- Container images: latest base version, minimal, non-root.
