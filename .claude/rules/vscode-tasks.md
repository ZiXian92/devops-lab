---
paths:
  - ".vscode/tasks.json"
  - "scripts/**"
---

# VS Code tasks and scripts

- Every task that needs input uses `${input:...}` prompts (promptString / pickString); never prompt inside the PowerShell script.
- Do not re-prompt for a value that already exists (e.g. Nexus admin password once nexus-tf/terraform.auto.tfvars.json exists).
- Startup order in Start-Services.ps1: compose first, then post-startup actions, then Apply-Terraform.ps1 as the last step.
- New per-system setup goes in as post-startup actions in Start-Services.ps1.
- Helm, terraform and chart tooling run in containers via `compose exec`, not on the host.
- Publish tasks take one chart (no "all" option); test tasks may offer "all".
- Keep each task's `detail` in tasks.json in sync with the script's behaviour.
