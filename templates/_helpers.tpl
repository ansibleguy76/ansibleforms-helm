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

{{- /*
  Labels shared by everything the chart creates, commonLabels included. They go
  on the metadata of every object and on the pod template, but never on a
  selector: a Deployment selector is immutable, so a label added there could
  never be changed or removed again.
*/}}
{{- define "ansibleforms.labels" -}}
helm.sh/chart: {{ include "ansibleforms.chart" . }}
app.kubernetes.io/part-of: {{ include "ansibleforms.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- /*
  commonAnnotations, for everything the chart creates. Empty by default, and
  `with` on the result skips the annotations key entirely when there is nothing
  to write, so an object that had no annotations still renders without one.
*/}}
{{- define "ansibleforms.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end -}}

{{- /*
  Pod level scheduling, shared by both Deployments. Reads its settings from the
  component passed in as .component, with .root carrying the top of the chart so
  the release wide imagePullSecrets is still reachable.
*/}}
{{- define "ansibleforms.podScheduling" -}}
{{- $c := .component | default dict -}}
{{- /*
  indent 2 on every block, including the lists. A sequence written at the same
  column as its key is valid YAML and looks fine, but a mapping written that way
  is not: nodeSelector came out empty and its contents became sibling keys of
  the pod spec. Indenting everything the same way removes the difference.
*/}}
{{- with ($c.imagePullSecrets | default .root.Values.imagePullSecrets) }}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $c.nodeSelector }}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $c.tolerations }}
tolerations:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $c.affinity }}
affinity:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $c.topologySpreadConstraints }}
topologySpreadConstraints:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $c.priorityClassName }}
priorityClassName: {{ . }}
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

{{- /*
  A root init container and runAsNonRoot cannot both be true.

  The chart used to ship a "prepare-persistent-volume" init container running as
  root purely to chown the volume, and fsGroup does that job now. Anyone
  upgrading with their own copy of values.yaml still has it, and the combination
  fails in a way that is hard to read: helm reports the release as deployed and
  the pod sits in Init:CreateContainerConfigError with

    Error: container's runAsUser breaks non-root policy

  Better to refuse the render and say which value to change.

  hasKey rather than a default: runAsUser 0 is exactly the value that `default`
  treats as absent, so the obvious spelling of this check never fires.
*/}}
{{- define "ansibleforms.assertNoRootInitContainer" -}}
{{- $c := .component | default dict -}}
{{- $key := .key -}}
{{- $podSec := ($c.podSecurityContext | default dict) -}}
{{- if $podSec.runAsNonRoot -}}
{{- range ($c.initContainers | default list) -}}
{{- $sc := (.securityContext | default dict) -}}
{{- if and (hasKey $sc "runAsUser") (eq (toString $sc.runAsUser) "0") -}}
{{- fail (printf "\n\ncontainers.%s.initContainers has \"%s\" running as root (runAsUser: 0), while containers.%s.podSecurityContext sets runAsNonRoot: true.\n\nThe kubelet refuses that combination outright and the pod never starts.\n\nThe chart no longer ships that init container. containers.%s.podSecurityContext.fsGroup asks the kubelet to take ownership of the volume instead, which is cheaper and is the only form the restricted Pod Security Standard accepts. Drop it from your values.\n\nIf your storage ignores fsGroup and you really need the chown, set containers.%s.podSecurityContext to null and keep the init container. It has to be null rather than {}, because Helm merges your values over the chart's own and an empty map changes nothing. The release will then not be installable where restricted is enforced.\n" $key .name $key $key $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /*
  The container security context and the pod one are a matched pair.

  containers.mysql.securityContext drops every capability and forbids privilege
  escalation, which is only safe because the pod already runs as uid 999. Clear
  the pod context alone and the image goes back to starting as root and dropping
  to the mysql user with setgid, which those very settings block:

    [ERROR] [Server] setgid: Operation not permitted
    [ERROR] [Server] Aborting

  A CrashLoopBackOff with that buried in the log is a bad afternoon, so refuse
  the render and name both values.

  The server is not caught by this and should not be: its container context
  establishes uid 1000 on its own, so it never needs to step down from root.
*/}}
{{- define "ansibleforms.assertSecurityContextsAgree" -}}
{{- $c := .component | default dict -}}
{{- $key := .key -}}
{{- $pod := ($c.podSecurityContext | default dict) -}}
{{- $ctr := ($c.securityContext | default dict) -}}
{{- $restricted := or (eq (toString (dig "allowPrivilegeEscalation" true $ctr)) "false") (has "ALL" (dig "capabilities" "drop" (list) $ctr)) -}}
{{- $nonRoot := or $pod.runAsNonRoot $ctr.runAsNonRoot -}}
{{- if and (hasKey $pod "runAsUser") (ne (toString $pod.runAsUser) "0") -}}{{- $nonRoot = true -}}{{- end -}}
{{- if and (hasKey $ctr "runAsUser") (ne (toString $ctr.runAsUser) "0") -}}{{- $nonRoot = true -}}{{- end -}}
{{- if and $restricted (not $nonRoot) -}}
{{- fail (printf "\n\ncontainers.%s.securityContext drops capabilities or forbids privilege escalation, but nothing makes the pod run as a non-root user.\n\nThe image starts as root and steps down to its own user with setgid, and those settings block exactly that. The container starts and dies with \"setgid: Operation not permitted\", over and over.\n\nThe two contexts belong together. Either keep both as the chart ships them, or clear both: set containers.%s.securityContext to null as well as containers.%s.podSecurityContext.\n" $key $key $key) -}}
{{- end -}}
{{- end -}}

{{- /*
  Annotations that make a configuration change actually reach the container.

  Nothing here rolled a pod when its configuration changed. The Secret would be
  updated and the running process kept the environment it started with; the
  my.cnf ConfigMap would be updated and the file inside the container never
  moved at all, because it is mounted with subPath and subPath mounts are frozen
  at pod creation. Measured on a live release: the ConfigMap asked for
  innodb_buffer_pool_size 256M, the file in the pod still read "[mysqld]" and
  MySQL was running on the 128M default.

  A checksum of what the chart renders, written into the pod template, turns
  that into an ordinary rollout.
*/}}
{{- define "ansibleforms.ownedConfigChecksums" -}}
{{- $root := .root -}}
{{- $out := dict -}}
{{- if dig "enabled" true ($root.Values.rollOnChange | default dict) -}}
{{- /*
  Renders to nothing when secrets.existingSecret is set, which is correct: the
  chart does not own that Secret and cannot see it from here. Turn on
  rollOnChange.external for that case.
*/}}
{{- $_ := set $out "checksum/secret" (include (print $root.Template.BasePath "/secrets.yaml") $root | sha256sum) -}}
{{- if .withMyCnf -}}
{{- $_ := set $out "checksum/my-cnf" (include (print $root.Template.BasePath "/mysql-configmap-my-cnf.yaml") $root | sha256sum) -}}
{{- end -}}
{{- if and .withForms (dig "external" false ($root.Values.rollOnChange | default dict)) -}}
{{- $_ := set $out "checksum/external-config" (include "ansibleforms.externalConfigChecksum" $root) -}}
{{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{- /*
  The same idea for the objects the chart does not own: a Secret supplied
  through secrets.existingSecret, and the ConfigMaps holding forms.yaml, the
  extra form definitions and custom.js.

  Reading them means a lookup against the cluster, and lookup returns nothing
  during `helm template`. Anything that renders first and applies afterwards,
  Argo CD and Flux included, would therefore see a checksum that differs from
  the one an install produces. That is why rollOnChange.external is off by
  default.
*/}}
{{- define "ansibleforms.externalConfigChecksum" -}}
{{- $parts := list -}}
{{- $secrets := (.Values.secrets | default dict) -}}
{{- if $secrets.existingSecret -}}
{{- $found := lookup "v1" "Secret" .Release.Namespace $secrets.existingSecret -}}
{{- if $found -}}{{- $parts = append $parts (toString ($found.data | default dict)) -}}{{- end -}}
{{- end -}}
{{- $forms := (.Values.forms | default dict) -}}
{{- range $key := (list "configMap" "extraFormsConfigMap" "customJs") -}}
{{- $mount := (dig $key (dict) $forms) -}}
{{- if and $mount.enabled $mount.name -}}
{{- $found := lookup "v1" "ConfigMap" $.Release.Namespace $mount.name -}}
{{- if $found -}}{{- $parts = append $parts (toString ($found.data | default dict)) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- $parts | join "|" | sha256sum -}}
{{- end -}}
