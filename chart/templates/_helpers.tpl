{{/*
Expand the name of the chart.
*/}}
{{- define "lab-authentik.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "lab-authentik.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "lab-authentik.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lab-authentik.labels" -}}
helm.sh/chart: {{ include "lab-authentik.chart" . }}
app.kubernetes.io/part-of: {{ include "lab-authentik.name" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Server selector labels
*/}}
{{- define "lab-authentik.serverSelectorLabels" -}}
app.kubernetes.io/name: {{ include "lab-authentik.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "lab-authentik.workerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "lab-authentik.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Secret name for Authentik credentials
*/}}
{{- define "lab-authentik.secretName" -}}
{{- if .Values.authentik.existingSecret }}
{{- .Values.authentik.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "lab-authentik.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection helpers
*/}}
{{- define "lab-authentik.postgresHost" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.name }}
{{- else }}
{{- .Values.externalPostgres.host }}
{{- end }}
{{- end }}

{{- define "lab-authentik.postgresPort" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.port }}
{{- else }}
{{- .Values.externalPostgres.port }}
{{- end }}
{{- end }}

{{- define "lab-authentik.postgresDb" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.db }}
{{- else }}
{{- .Values.externalPostgres.db }}
{{- end }}
{{- end }}

{{- define "lab-authentik.postgresUser" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.user }}
{{- else }}
{{- .Values.externalPostgres.user }}
{{- end }}
{{- end }}

{{- define "lab-authentik.postgresPassword" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.password }}
{{- else }}
{{- .Values.externalPostgres.password }}
{{- end }}
{{- end }}
