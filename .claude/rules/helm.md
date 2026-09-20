---
paths:
  - "app-deployment-template-charts/**"
  - "images/helm-cicd/**"
---

# Helm charts

Baseline for every chart:
- Must pass OpenShift restricted-v3 SCC and restricted PSA. seccompProfile and hostUsers are hardcoded, not values.
- Namespace-aware; one app per namespace.
- Hardcoded: PDB (maxUnavailable: 1), Service (ClusterIP, port 80), serviceAccount token automount (false).
- Do not create ServiceAccounts, only reference by name.
- Topology spread: maxSkew 1, ScheduleAnyway.
- Group nodeSelector, affinity and tolerations under one `placement` object.
- Probes disabled by default.
- ConfigMap and Secret support mount mode `env` or `volume` (default volume, configurable mount path). Comment yq usage for secrets.
- Single `ingress` values block covering Ingress, Gateway API and OpenShift Route:
  - Host required, path always `/`, port 443 with TLS else 80.
  - TLS terminates at the ingress, no http→https redirect. The chart builds its own TLS secret from user-supplied key and cert.
  - Gateway API: chart creates its own ListenerSet (apiVersion and kind hardcoded).
  - Route may omit host and TLS material to use router defaults.
  - Ingress annotations are specified centrally and applied only where needed; no per-resource annotation values.
- Every chart ships values.schema.json and helm-unittest tests under tests/ (lint + unittest + kubeconform). Prefer `asserts` anchors and shared invariants over combinatorial cases.
- Publish target: Nexus `oci-internal`, prefix `helm/deployment-templates`, localhost:8081 (insecure HTTP). Publish one chart at a time; version is stamped into Chart.yaml at publish time, never by PR.
