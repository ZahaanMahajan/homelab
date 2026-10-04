{{/*
Expand the name of the chart.
*/}}
{{- define "linkding.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "linkding.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "linkding.name" . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "linkding.selectorLabels" -}}
app: {{ include "linkding.name" . }}
{{- end }}
