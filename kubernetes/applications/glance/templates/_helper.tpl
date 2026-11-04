{{/* Chart name */}}
{{- define "glance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified name. With release "glance" this resolves to "glance". */}}
{{- define "glance.fullname" -}}
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

{{/*
Selector labels. Deployment selectors are immutable, so these are kept
identical to the original manifests (name only).
*/}}
{{- define "glance.selectorLabels" -}}
app.kubernetes.io/name: {{ include "glance.name" . }}
{{- end }}

{{/* Common labels */}}
{{- define "glance.labels" -}}
{{ include "glance.selectorLabels" . }}
app.kubernetes.io/part-of: {{ .Values.partOf }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Image reference; tag defaults to v<appVersion> */}}
{{- define "glance.image" -}}
{{- printf "%s:%s" .Values.image.repository (default (printf "v%s" .Chart.AppVersion) .Values.image.tag) }}
{{- end }}
