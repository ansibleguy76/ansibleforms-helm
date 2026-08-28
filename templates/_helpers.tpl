{{- /*
  Names and labels, in one place.

  Every resource used to spell its own name and repeat its own label block, and
  the two drifted: the PVCs claimed app.kubernetes.io/instance: server, the
  Services claimed instance: mysql, and only the server Deployment carried
  managed-by and version. Worse, the Deployments, Services and ConfigMaps were
  named with plain literals ("server", "mysql", "mysql-my-cnf"), so two releases
  in one namespace fought over the same objects and each Service selected the
  other release's pods.
*/}}

{{- /*
  The value of app.kubernetes.io/name. The chart name unless overridden.
*/}}
{{- define "ansibleforms.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
  The prefix every resource name is built from.

  This is the release name, not the usual "<release>-<chart>" of a scaffolded
  chart, and that is deliberate. The Secret, the Ingress and both PVCs have
  always been named "<release>-secrets", "<release>-ingress" and
  "<release>-{server,mysql}-pvc". Moving them to "<release>-<chart>-..." would
  rename the PVCs, and a renamed PVC is a new empty volume with the old one
  deleted underneath it. Keeping the release name as the prefix means this
  change renames only the objects that were actually broken, all of them
  stateless, and every existing volume is picked up exactly where it was.

  Set fullnameOverride if you want something else entirely.
*/}}
{{- define "ansibleforms.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ansibleforms.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /* Per component names. Truncated again: fullname can already be 63 long. */}}
{{- define "ansibleforms.server.fullname" -}}
{{- printf "%s-server" (include "ansibleforms.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ansibleforms.mysql.fullname" -}}
{{- printf "%s-mysql" (include "ansibleforms.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
  Storage, Secret and Ingress names. Unchanged from what the chart has always
  produced, for the reason spelled out above. They go through helpers anyway so
  there is a single place to look, and so the templates stop hand rolling
  printf on .Release.Name.
*/}}
{{- define "ansibleforms.server.pvcName" -}}
{{- printf "%s-server-pvc" (include "ansibleforms.fullname" .) -}}
{{- end -}}

{{- define "ansibleforms.mysql.pvcName" -}}
{{- printf "%s-mysql-pvc" (include "ansibleforms.fullname" .) -}}
{{- end -}}

{{- define "ansibleforms.ingressName" -}}
{{- printf "%s-ingress" (include "ansibleforms.fullname" .) -}}
{{- end -}}

{{- /*
  The Secret the server and MySQL both read. Either one the chart generates or
  one managed outside it (External Secrets, Sealed Secrets, SOPS).
*/}}
{{- define "ansibleforms.secretName" -}}
{{- $secrets := .Values.secrets | default dict -}}
{{- $secrets.existingSecret | default (printf "%s-secrets" (include "ansibleforms.fullname" .)) -}}
{{- end -}}

{{- /* Labels shared by everything the chart creates. */}}
{{- define "ansibleforms.labels" -}}
helm.sh/chart: {{ include "ansibleforms.chart" . }}
app.kubernetes.io/part-of: {{ include "ansibleforms.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end -}}

{{- /*
  Selector labels. A Deployment selector is immutable once created, so nothing
  release specific or version specific may appear here beyond the three below.
*/}}
{{- define "ansibleforms.server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ansibleforms.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: server
{{- end -}}

{{- define "ansibleforms.mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ansibleforms.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end -}}

{{- define "ansibleforms.server.labels" -}}
{{ include "ansibleforms.labels" . }}
{{ include "ansibleforms.server.selectorLabels" . }}
{{- end -}}

{{- define "ansibleforms.mysql.labels" -}}
{{ include "ansibleforms.labels" . }}
{{ include "ansibleforms.mysql.selectorLabels" . }}
{{- end -}}

{{- /*
  HTTPS is documented as 0/1 and people write it unquoted, which makes it a
  number in YAML. toString takes both forms.
*/}}
{{- define "ansibleforms.server.https" -}}
{{- $env := (((.Values.applications | default dict).server | default dict).env | default dict) -}}
{{- if eq (toString ($env.HTTPS | default "0")) "1" -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- /*
  The port the application listens on, and the scheme to reach it with. Derived
  in one place so the container, the Service and every probe cannot disagree.
  The Ingress does not use these at all any more: it points at the Service port
  by name, which is what stopped it from hardcoding 80 against a Service that
  had moved to 443.
*/}}
{{- define "ansibleforms.server.port" -}}
{{- if eq (include "ansibleforms.server.https" .) "true" -}}443{{- else -}}80{{- end -}}
{{- end -}}

{{- define "ansibleforms.server.scheme" -}}
{{- if eq (include "ansibleforms.server.https" .) "true" -}}HTTPS{{- else -}}HTTP{{- end -}}
{{- end -}}

{{- /*
  The host the server connects to. Defaults to the MySQL this chart deploys,
  whose Service name now follows the release, so it can no longer be a literal.
*/}}
{{- define "ansibleforms.mysql.host" -}}
{{- $mysql := ((.Values.applications | default dict).mysql | default dict) -}}
{{- $mysql.host | default (include "ansibleforms.mysql.fullname" .) -}}
{{- end -}}
