{{/*
Chart name.
*/}}
{{- define "nextcloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified application name.
*/}}
{{- define "nextcloud.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "nextcloud.name" . }}
{{- end }}
{{- end }}

{{/*
Common selector labels.
*/}}
{{- define "nextcloud.selectorLabels" -}}
app: {{ include "nextcloud.name" . }}
{{- end }}
