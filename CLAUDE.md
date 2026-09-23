# devops-lab

Local lab: Podman + KinD + Nexus OSS (plain HTTP) + Vault + Jenkins + Terraform + Helm chart templates. Windows 11, PowerShell.

- scripts/: PowerShell entry points, one VS Code task each (.vscode/tasks.json)
- docker-compose.yaml: Nexus, the helm-cicd tool container (images/helm-cicd), Jenkins (controller + agent, images/jenkins-*, JCasC in jenkins/casc/), and Vault (config in vault/config/); run with podman compose
- kind/kind-config.yaml: project-scoped cluster, network `kind-devops-lab`
- *-tf/: Terraform per system
- app-deployment-template-charts/: Helm charts

Path-scoped conventions are in .claude/rules/ (helm, terraform, vscode-tasks).

## Working style
- For "how/why/is X true" questions, answer and verify; do not edit files unless asked.
- For non-obvious choices (hardcode vs value, keep vs remove), give a one-line recommendation instead of asking.
- Container images: latest base version, minimal, non-root.
