{{/* Chart name, truncated to fit the 63 char DNS label limit. */}}
{{- define "web-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified resource name. */}}
{{- define "web-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "web-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "web-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "web-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "web-app.labels" -}}
helm.sh/chart: {{ include "web-app.chart" . }}
{{ include "web-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "web-app.serviceAccountName" -}}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}

{{- define "web-app.configMapName" -}}
{{- printf "%s-config" (include "web-app.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "web-app.secretName" -}}
{{- printf "%s-secret" (include "web-app.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "web-app.tlsSecretName" -}}
{{- printf "%s-tls" (include "web-app.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Mandatory ingress hostname (all ingress types). */}}
{{- define "web-app.ingressHost" -}}
{{- required "ingress.host is required when ingress.enabled=true" .Values.ingress.host -}}
{{- end }}

{{/* Mandatory TLS material; fails the render if either PEM is missing. */}}
{{- define "web-app.tlsCertificate" -}}
{{- required "ingress.tls.certificate is required when ingress.tls.enabled=true" .Values.ingress.tls.certificate -}}
{{- end }}
{{- define "web-app.tlsKey" -}}
{{- required "ingress.tls.key is required when ingress.tls.enabled=true" .Values.ingress.tls.key -}}
{{- end }}

{{/*
Validated ingress type: ingress | gateway | route.
Every ingress template calls this so a typo fails the render instead of silently exposing nothing.
*/}}
{{- define "web-app.ingressType" -}}
{{- $t := .Values.ingress.type | default "ingress" -}}
{{- if not (has $t (list "ingress" "gateway" "route")) -}}
{{- fail (printf "ingress.type must be one of: ingress, gateway, route (got %q)" $t) -}}
{{- end -}}
{{- $t -}}
{{- end }}
