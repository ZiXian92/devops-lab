#!/bin/sh
# tasks - lint, test, package and publish the Helm charts under $CHARTS_DIR.
#
# Runs inside the helm-cicd container (see docker-compose.yaml):
#   podman compose exec helm-cicd tasks <command> [chart]
#
# POSIX sh on purpose: the image is Alpine (busybox), there is no bash.
set -eu

CHARTS_DIR="${CHARTS_DIR:-/workspace/app-deployment-template-charts}"
DIST_DIR="${DIST_DIR:-/tmp/dist}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.37.0}"   # the kind cluster's version

# Nexus OCI repo the charts are pushed to: oci://<host>/<repo>/<path>. The chart name is
# appended by `helm push`. `nexus` is the compose service name on the shared network.
HELM_OCI_REPO="${HELM_OCI_REPO:-oci://nexus:8081/oci-internal/helm/deployment-templates}"
HELM_PLAIN_HTTP="${HELM_PLAIN_HTTP:-true}"           # local Nexus has no TLS
# Docker-style auth file written by nexus-tf (helm-access.tf) for helm-publisher.
NEXUS_CREDENTIALS="${NEXUS_CREDENTIALS:-/run/nexus-credentials/publisher.json}"

REGISTRY_CFG=""
SCRATCH=""
trap '[ -z "$REGISTRY_CFG" ] || rm -f "$REGISTRY_CFG"; [ -z "$SCRATCH" ] || rm -rf "$SCRATCH"' EXIT

step() { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: tasks <command> [chart]

Commands:
  lint       helm lint --strict
  unittest   helm-unittest suites in <chart>/tests
  validate   render the chart (default values + each tests/values/*.yaml) and check the
             manifests against the Kubernetes schemas (kubeconform)
  all        lint + unittest + validate
  package    helm package into $DIST_DIR
  publish    all + package + helm push to $HELM_OCI_REPO (Nexus), one chart at a time, at
             the version in its Chart.yaml (scripts/Publish-Chart.ps1 sets that first)
  help       this text

[chart] is a directory name under $CHARTS_DIR; default: every chart found there
(except for publish, which requires one).
Settings (environment): CHARTS_DIR, DIST_DIR, KUBERNETES_VERSION, HELM_OCI_REPO,
HELM_PLAIN_HTTP, NEXUS_CREDENTIALS.
EOF
}

# --- chart discovery ----------------------------------------------------------
chart_dirs() {
  if [ -n "${1:-}" ]; then
    [ -f "$CHARTS_DIR/$1/Chart.yaml" ] || die "no chart '$1' in $CHARTS_DIR"
    echo "$CHARTS_DIR/$1"
    return
  fi
  found=0
  for f in "$CHARTS_DIR"/*/Chart.yaml; do
    [ -e "$f" ] || break
    found=1
    dirname "$f"
  done
  [ "$found" = 1 ] || die "no charts found in $CHARTS_DIR (is the repo mounted?)"
}

# for_each_chart <task-function> [chart]
for_each_chart() {
  fn=$1
  for dir in $(chart_dirs "${2:-}"); do
    step "$(basename "$dir"): ${fn#task_}"
    "$fn" "$dir"
  done
}

# --- tasks (each takes the chart directory) ------------------------------------
task_lint() {
  helm lint --strict "$1"
}

task_unittest() {
  # helm-unittest creates tests/__snapshot__ next to the suites even when no snapshots are
  # used, and the charts are mounted read-only: test a scratch copy instead.
  SCRATCH=$(mktemp -d)
  cp -R "$1" "$SCRATCH/"
  helm unittest "$SCRATCH/$(basename "$1")"
  rm -rf "$SCRATCH"
  SCRATCH=""
}

task_validate() {
  # CRDs (Gateway API, OpenShift Route) have no schema in the default catalogue, so those
  # kinds are skipped instead of failing.
  for values in "" "$1"/tests/values/*.yaml; do
    [ -z "$values" ] || [ -e "$values" ] || continue
    printf '  values: %s\n' "${values:-<chart defaults>}"
    if [ -z "$values" ]; then
      helm template validate "$1" --namespace validate
    else
      helm template validate "$1" --namespace validate --values "$values"
    fi | kubeconform -strict -summary -ignore-missing-schemas \
           -kubernetes-version "$KUBERNETES_VERSION"
  done
}

task_package() {
  mkdir -p "$DIST_DIR"
  out=$(helm package "$1" --destination "$DIST_DIR")
  echo "$out"
  PACKAGE=${out##*saved it to: }
}

task_push() {
  task_package "$1"
  set -- "$PACKAGE" "$HELM_OCI_REPO" --registry-config "$REGISTRY_CFG"
  [ "$HELM_PLAIN_HTTP" != true ] || set -- "$@" --plain-http
  helm push "$@"
}

# The credentials file is keyed by the host name Terraform knew (localhost:8081); inside the
# compose network Nexus is reached as nexus:8081, so re-key the same auth token.
prepare_registry_config() {
  [ -r "$NEXUS_CREDENTIALS" ] || die "cannot read $NEXUS_CREDENTIALS. Apply nexus-tf first (scripts/Apply-Terraform.ps1) and make sure the file is readable by uid $(id -u)."
  auth=$(sed -n 's/.*"auth"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$NEXUS_CREDENTIALS")
  [ -n "$auth" ] || die "no auth token found in $NEXUS_CREDENTIALS"
  host=${HELM_OCI_REPO#oci://}
  host=${host%%/*}
  REGISTRY_CFG=$(mktemp)
  printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$host" "$auth" > "$REGISTRY_CFG"
}

# --- main ---------------------------------------------------------------------
cmd=${1:-help}
[ $# -eq 0 ] || shift
chart=${1:-}
# Charts have their own version cadence, so publishing is always one chart at a time.
[ "$cmd" != publish ] || [ -n "$chart" ] || die "publish needs a chart: tasks publish <chart>"

case "$cmd" in
  lint|unittest|validate|package)
    for_each_chart "task_$cmd" "$chart"
    ;;
  all)
    for t in lint unittest validate; do for_each_chart "task_$t" "$chart"; done
    ;;
  publish)
    prepare_registry_config   # fail early, before running anything
    for t in lint unittest validate; do for_each_chart "task_$t" "$chart"; done
    for_each_chart task_push "$chart"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
