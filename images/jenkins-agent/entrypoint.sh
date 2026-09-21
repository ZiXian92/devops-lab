#!/bin/sh
# Look up this node's inbound-agent secret on the controller, then start the official
# agent entrypoint (jenkins-agent) with it.
#
# The secret is derived from the controller's own key, so it cannot be written into the
# JCasC file up front; the agent fetches it instead, as the low-privilege `agent-connector`
# user (Overall/Read + Agent/Connect only), whose password is in a file mounted by
# docker-compose.yaml. Set JENKINS_SECRET to skip the lookup.
#
# POSIX sh on purpose (matches the other lab containers).
set -eu

: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_AGENT_NAME:?JENKINS_AGENT_NAME is required}"
CONNECTOR_USER="${JENKINS_CONNECTOR_USER:-agent-connector}"
CONNECTOR_PASSWORD_FILE="${JENKINS_CONNECTOR_PASSWORD_FILE:-/run/jenkins-secrets/agent-connector-password}"

if [ -z "${JENKINS_SECRET:-}" ]; then
  jnlp="${JENKINS_URL%/}/computer/${JENKINS_AGENT_NAME}/jenkins-agent.jnlp"
  password=$(cat "$CONNECTOR_PASSWORD_FILE")
  attempt=0
  while :; do
    # -K - keeps the password out of the process list. Jenkins answers 4xx/5xx until it
    # has finished starting and applied JCasC, so retry.
    if body=$(printf 'user = "%s:%s"\n' "$CONNECTOR_USER" "$password" | curl -fsS -K - "$jnlp" 2>/dev/null); then
      JENKINS_SECRET=$(printf '%s' "$body" | sed -n 's|.*<argument>\([0-9a-f]\{64\}\)</argument>.*|\1|p' | head -n1)
      [ -z "$JENKINS_SECRET" ] || break
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -lt 60 ] || { echo "error: no agent secret from $jnlp after $attempt tries" >&2; exit 1; }
    echo "waiting for the controller ($jnlp)..." >&2
    sleep 5
  done
  export JENKINS_SECRET
fi

exec /usr/local/bin/jenkins-agent "$@"
