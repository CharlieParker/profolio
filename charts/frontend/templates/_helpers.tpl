{{/*
Install with release name "frontend" (helm install frontend ./charts/frontend) so this
resolves to plain "frontend" — matching the raw manifests' object names exactly.
*/}}
{{- define "frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "frontend.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "frontend.labels" -}}
app.kubernetes.io/name: {{ include "frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "frontend.selectorLabels" -}}
app: {{ include "frontend.fullname" . }}
{{- end -}}

{{/*
Image reference: repository:tag, plus @digest when image.digest is set. With a digest the
container runtime pulls exactly those bytes and ignores the tag, which is then only a
human-readable label (the commit the image was built from). Without one it pulls by tag.
A set digest must look like one, so a bad paste fails the render (and CI), not the pull.
*/}}
{{- define "frontend.image" -}}
{{- $ref := printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- with .Values.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .) -}}
{{- fail (printf "image.digest must be sha256:<64 hex chars>, got %q" .) -}}
{{- end -}}
{{- $ref = printf "%s@%s" $ref . -}}
{{- end -}}
{{- $ref -}}
{{- end -}}
