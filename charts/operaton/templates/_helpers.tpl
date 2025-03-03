{{/*
Expand the name of the chart.
*/}}
{{- define "operaton.name" -}}
{{- default .Chart.Name .Values.general.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "operaton.fullname" -}}
{{- if .Values.general.fullnameOverride }}
{{- .Values.general.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.general.nameOverride }}
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
{{- define "operaton.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "operaton.labels" -}}
helm.sh/chart: {{ include "operaton.chart" . }}
{{ include "operaton.selectorLabels" . }}
{{ include "operaton.customLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "operaton.selectorLabels" -}}
app.kubernetes.io/name: {{ include "operaton.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Custom labels
*/}}
{{- define "operaton.customLabels" -}}
{{- if .Values.commonLabels }}
{{- range $key, $val := .Values.commonLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "operaton.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "operaton.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if H2 database is used
Note that Helm template always retruns string, so this is not really a bool.
*/}}
{{- define "operaton.h2DatabaseIsUsed" -}}
{{- if (hasPrefix "jdbc:h2" .Values.database.url) -}}
true
{{- else -}}
false
{{- end }}
{{- end }}

{{/*
Check if the deployment will have volumes
Note that Helm template always retruns string, so this is not really a bool.
*/}}
{{- define "operaton.withVolumes" -}}
{{ if or (eq (include "operaton.h2DatabaseIsUsed" .) "true") (not (empty .Values.extraVolumeMounts)) (not (empty .Values.extraVolumes)) -}}
true
{{- else -}}
false
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for ingress according to Kubernetes version.
*/}}
{{- define "operaton.ingress.apiVersion" -}}
{{- if .Values.ingress.enabled -}}
{{- if semverCompare "<1.14-0" .Capabilities.KubeVersion.Version -}}
{{- print "extensions/v1beta1" -}}
{{- else if semverCompare "<1.19-0" .Capabilities.KubeVersion.Version -}}
{{- print "networking.k8s.io/v1beta1" -}}
{{- else -}}
{{- print "networking.k8s.io/v1" -}}
{{- end }}
{{- end }}
{{- end }}
