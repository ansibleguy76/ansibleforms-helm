# AnsibleForms Helm Chart

This Helm chart deploys the AnsibleForms application and its MySQL database on Kubernetes. It is designed for flexibility, security, and ease of use in both development and production environments.

## Features

- Deploys AnsibleForms and MySQL with configurable images and resources
- Handles all sensitive data (DB credentials, admin credentials, encryption secret) via Kubernetes Secrets
- All application environment variables are configurable via `values.yaml`
- Storage class and size for both server and MySQL are configurable
- Supports both **dynamic provisioning** (StorageClass-based) and **pre-created static PVs**
- Ingress is optional and highly customizable (hostname, TLS, annotations, etc.)
- Service type (ClusterIP, LoadBalancer, NodePort) is configurable, with support for static LoadBalancer IPs
- (Optional) Support for managing `forms.yaml`, `forms/*.yaml` definitions, and `custom.js` via ConfigMaps

## Installing

From the chart repository:

```bash
helm repo add ansibleforms https://ansibleguy76.github.io/ansibleforms-helm/
helm repo update
helm show values ansibleforms/ansibleforms > my_values.yaml
# edit my_values.yaml, then
helm upgrade --install ansibleforms ansibleforms/ansibleforms \
  --namespace ansibleforms --create-namespace \
  --values my_values.yaml
```

Or straight from the OCI registry, no repository to add:

```bash
helm show values oci://ghcr.io/ansibleguy76/charts/ansibleforms > my_values.yaml
helm upgrade --install ansibleforms oci://ghcr.io/ansibleguy76/charts/ansibleforms \
  --namespace ansibleforms --create-namespace \
  --values my_values.yaml
```

Pin the chart version in anything that runs unattended, for example
`--version 6.2.2`, so a new release never lands on its own.

## Usage

### 1. Clone the Helm chart and values.yaml

Only needed if you want to work on the chart itself rather than install it.

```bash
git clone https://github.com/ansibleguy76/ansibleforms-helm
cp ./ansibleforms-helm/values.yaml my_values.yaml
```

### 2. Configure your values

Update the `my_values.yaml` to your taste.

#### Minimalistic example without ingress (dynamic storage with a StorageClass)

```yaml
applications:
  server:
    env:
      HTTPS: 1 # auto sets port to 443
      ENCRYPTION_SECRET: "Abc123Abc123Abc123Abc123Abc123Abc1" # optional but recommended, 32 chars random string

storages:
  server:
    className: longhorn   # example dynamic StorageClass
    size: 5Gi
  mysql:
    className: longhorn
    size: 5Gi

services:
  server:
    type: LoadBalancer
    loadbalancer:
      ip: 10.0.0.1        # AnsibleForms will be available at https://10.0.0.1
```

#### Extended example with ingress

```yaml
applications:
  server:
    env:
      HTTPS: 0 # auto sets ports on 80 or 443
      # ...other env vars (see values.yaml for all options)
      ENCRYPTION_SECRET: "Abc123Abc123Abc123Abc123Abc123Abc1"
      ADMIN_USERNAME: admin
      ADMIN_PASSWORD: MyAppPassword1!!
  mysql:
    user: root
    password: MyDbPassword1!!

storages:
  server:
    className: nfs-csi       # just an example storage provider
    size: 1Gi
  mysql:
    className: nfs-csi-nomap # just an example storage provider
    size: 1Gi

containers:
  server:
    image: ansibleguy/ansibleforms:6.2.1
    resources:
      limits:
        cpu: "0.5"
        memory: 512Mi
      requests:
        cpu: "0.25"
        memory: 256Mi
  mysql:
    image: mysql:8.4
    resources:
      limits:
        cpu: "0.5"
        memory: 512Mi
      requests:
        cpu: "0.25"
        memory: 256Mi

services:
  server:
    type: ClusterIP # service is exposed with ingress
  mysql:
    type: ClusterIP

ingress:
  enabled: true # enable ingress
  className: nginx
  hostname: ansibleforms.example.com
  path: /
  pathType: Prefix
  tls:
    enabled: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
  issuer: letsencrypt-prod
  extraHosts: [] # ["other.example.com"]
  extraPaths: [] # [{ path: /api, serviceName: ansibleforms-server, servicePort: 80 }]
  extraAnnotations: {}
```

### 3. Storage configuration: dynamic provisioning vs static PVs

The chart supports two storage modes for both `server` and `mysql`:

1. **Dynamic provisioning (default)** – uses a Kubernetes StorageClass to dynamically provision PVs.
2. **Static PVs** – binds to pre-created PersistentVolumes by name.

#### 3.1 Dynamic provisioning (recommended for Longhorn / NFS-CSI, etc.)

Dynamic provisioning is the default mode. You typically configure:

```yaml
storages:
  server:
    className: longhorn   # or any other existing StorageClass
    size: 5Gi
    static:
      enabled: false
  mysql:
    className: longhorn
    size: 5Gi
    static:
      enabled: false
```

- If `storages.<component>.className` is set, the PVC will use that StorageClass.
- If `className` is omitted, the cluster's **default StorageClass** (if any) will be used.
- `static.enabled: false` (default) means **no `volumeName` is set**, so the cluster can bind the PVC to dynamically provisioned PVs.

#### 3.2 Static PVs (pre-created PersistentVolumes)

If you prefer to manage your own PersistentVolumes (for example, an NFS export or a hostPath PV), you can pre-create a PV and then tell the chart to bind to it.

Example: pre-create a static PV for MySQL:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ansibleforms-mysql-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ""                     # empty for static binding
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 10.0.0.10
    path: /exports/ansibleforms-mysql
```

Then configure the chart to use it:

```yaml
storages:
  mysql:
    size: 5Gi
    static:
      enabled: true
      volumeName: ansibleforms-mysql-pv    # must match the PV metadata.name
      storageClassName: ""                 # must match the PV storageClassName
```

When `static.enabled: true`:

- The PVC will include a `volumeName` (defaulting to `<release>-mysql-pv` / `<release>-server-pv` if `volumeName` is empty).
- The PVC will use `static.storageClassName` (or `""` if not provided).
- This binds the PVC directly to the specified pre-created PV.

You can configure the same pattern for the `server` volume:

```yaml
storages:
  server:
    size: 5Gi
    static:
      enabled: true
      volumeName: ansibleforms-server-pv
      storageClassName: ""
```

If you do **not** need static PVs, simply leave `static.enabled: false` and use the dynamic provisioning mode.

---

### 4. Using ConfigMaps for `forms.yaml`, form definitions, and `custom.js` (optional)

AnsibleForms uses a main configuration file (`forms.yaml`) and can also load additional form definitions from a `forms/` directory inside the persistent folder. It also supports a `custom.js` file for client-side customization, typically mounted at `/app/dist/src/functions/custom.js` as described in the AnsibleForms FAQ.

This chart provides optional values to mount those files from ConfigMaps:

```yaml
forms:
  configMap:
    enabled: true
    name: ansibleforms-forms                # ConfigMap containing the main forms.yaml
    key: forms.yaml                         # key in the ConfigMap
    mountPath: /app/dist/persistent/forms.yaml

  extraFormsConfigMap:
    enabled: true
    name: ansibleforms-forms-defs           # ConfigMap containing multiple form YAMLs
    mountPath: /app/dist/persistent/forms   # mounted as a directory

  customJs:
    enabled: true
    name: ansibleforms-custom-js            # ConfigMap containing custom.js
    key: custom.js                          # key in the ConfigMap
    mountPath: /app/dist/src/functions/custom.js
```

When any of the `enabled` flags are `false` (the default), the chart behaves as before and does not mount the corresponding ConfigMap.

#### 4.1 Example: main forms configuration (`forms.yaml`)

The following ConfigMap provides the main `forms.yaml` file, which defines categories, roles, and constants:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-forms
  namespace: ansibleforms
data:
  forms.yaml: |
    categories:
      - name: Default
        icon: bars
      - name: Demo
        icon: heart
      - name: Maintenance
        icon: cogs
      - name: Internal
        icon: cogs
      - name: Vmware
        icon: cogs
    roles:
      - name: admin
        groups:
          - local/admins
          - ldap/k8admins
      - name: demo
        groups:
          - local/demo
      - name: public
        groups: []
      - name: internal
        groups:
          - ldap/internal
        users:
          - ldap/FRoca
    constants:
      AF_PLAYBOOKS: /app/dist/persistent/playbooks
```

With the `forms.configMap` values set as shown earlier, this `forms.yaml` will be mounted at `/app/dist/persistent/forms.yaml`, which is the default location used by AnsibleForms.

#### 4.2 Example: additional form definitions (`forms/*.yaml`)

You can keep each form definition in a separate YAML file within a second ConfigMap. Each key under `data:` becomes a file inside `/app/dist/persistent/forms/`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-forms-defs
  namespace: ansibleforms
data:
  awx-call-user_creation.yaml: |
    name: User Creation
    type: awx
    template: "jt-or_myawesomeor-create_user"
    roles:
      - internal
    categories:
      - Internal
    help: "Form to create FTP users"
    description: "Launch ftp user creation"
    fields:
      - name: survey_user
        label: Username
        type: text
        required: true
      - name: survey_password
        label: Password
        type: text
        required: true
      - name: survey_type
        label: Type
        type: enum
        values:
          - name: general
            value: general
          - name: av
            value: av
        required: true

  # more forms here, one per key:
  # otherform.yaml: |
  #   name: ...
  #   ...
```

#### 4.3 Example: `custom.js` for client-side customization

To inject a `custom.js` file into AnsibleForms, create a ConfigMap like:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-custom-js
  namespace: ansibleforms
data:
  custom.js: |
    // Example custom JavaScript for AnsibleForms
    window.afCustom = window.afCustom || {};
    window.afCustom.onFormLoad = function (form) {
      console.log("Form loaded:", form.name);
    };
```

With `forms.customJs.enabled: true` and the values shown above, this file will be mounted at `/app/dist/src/functions/custom.js`, matching the location described in the AnsibleForms documentation.

### 5. Install the Chart

Depending on your environment, choose an existing namespace or choose to create a new one.

```bash
helm install ansibleforms ./ansibleforms-helm -f ./my_values.yaml -n ansibleforms --create-namespace
```

### 6b. Letting the chart make up the credentials

`secrets.generate: true` invents whatever you have not supplied, on the first
install, and reads it back on every upgrade afterwards so it never changes:

```bash
helm upgrade --install ansibleforms ansibleforms/ansibleforms \
  --namespace ansibleforms --create-namespace \
  --set secrets.generate=true

kubectl -n ansibleforms get secret ansibleforms-secrets \
  -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d
```

**This does not work with Argo CD or Flux, and the chart will tell you so.**
Both render with `helm template`, where there is no cluster to read, and the
chart would mint a different secret every time. `ENCRYPTION_SECRET` is not a
password you can reset: it is the key AnsibleForms encrypts stored credentials
with, `aes-256-ctr` does not authenticate, and decrypting with the wrong key
returns rubbish instead of raising anything. For GitOps use
`secrets.existingSecret` as described just above; that is what External Secrets
with Vault, Sealed Secrets and SOPS are for, and the chart never touches a
Secret it did not create.

The generated Secret is annotated `helm.sh/resource-policy: keep`, so
`helm uninstall` leaves it behind and a reinstall picks the same key back up.
Delete it by hand when you really do mean to start over. It exists nowhere else:
back it up.

`ENCRYPTION_SECRET` is generated at exactly 32 characters, which is what
AnsibleForms uses as an aes-256 key. Shorter and it pads the rest with a
constant from its own source code, so a ten character secret is ten characters
of secret and twenty-two of public knowledge. Longer and the remainder is cut
off. The chart says so after an install if yours is not 32.

### 6. Credentials from a Secret you already manage

By default the chart builds a Secret named `<release>-secrets` out of the
passwords in your values file. Point `secrets.existingSecret` at a Secret you
manage instead and the chart creates none, which is what you want with External
Secrets, Sealed Secrets, SOPS or a Vault sidecar:

```yaml
secrets:
  existingSecret: ansibleforms-credentials
```

The Secret has to carry these five keys:

| Key | |
|---|---|
| `DB_USER` | database user |
| `DB_PASSWORD` | database password, also used by the bundled MySQL as its root password |
| `ENCRYPTION_SECRET` | encrypts credentials stored inside AnsibleForms |
| `ADMIN_USERNAME` | local admin account |
| `ADMIN_PASSWORD` | local admin password |

With this set you can drop `applications.mysql.password` and the sensitive
entries under `applications.server.env` from your values entirely.

Worth knowing if you manage that Secret yourself: the name the chart generates
is `<release>-secrets`, which is very often the same name people give theirs. If
you do not set `existingSecret`, the chart will happily create its own Secret
under that name and overwrite yours on the next sync. Since 6.2.1 it at least
refuses to write the placeholder passwords from `values.yaml` into it.

### 7. Using a database the chart does not manage

Set `mysql.enabled: false` and no MySQL Deployment, Service, PVC or ConfigMap is
created. Point AnsibleForms at your own server:

```yaml
mysql:
  enabled: false

applications:
  mysql:
    host: mysql.databases.svc.cluster.local
    port: "3306"
    user: ansibleforms
    password: ...   # or supply it through secrets.existingSecret
```

**Create the schema first.** AnsibleForms migrates an existing schema forward
but does not create one from nothing. The bundled MySQL gets it from the chart's
init script, which your own server never sees, so apply
[`files/schema.sql`](files/schema.sql) once before starting the application:

```bash
mysql -h your-db-host -u root -p < files/schema.sql
```

It creates the `AnsibleForms` database and its tables, creates nothing that is
already there, and drops nothing, so re-running it is harmless. It grants no
privileges either; give your AnsibleForms user access to that database yourself.

Skip this and the symptom is confusing: the pod starts, passes its probes and
serves the front page, because that page is static, while every query behind it
fails with `Table 'AnsibleForms.jobs' doesn't exist`.

**Disabling MySQL on a release that already runs it deletes the PVC**, and with
a reclaim policy of `Delete` the data goes with it. Take a dump first.

### 8. Serving HTTPS behind an ingress

`applications.server.env.HTTPS: 1` makes AnsibleForms terminate TLS itself, and
the container, its Service and its probes all move to 443. The Ingress follows
automatically, because it refers to the Service port by name rather than by
number.

What does not follow automatically is your ingress controller: it still has to
be told to speak TLS to the backend instead of plain HTTP, and the certificate
AnsibleForms serves is self-signed. Where that setting lives depends on the
controller.

On ingress-nginx it is an annotation on the Ingress:

```yaml
ingress:
  extraAnnotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
```

On Traefik the `service.*` settings are read from the **Service**, not from the
Ingress, so they go under `services.server.annotations`. Skipping verification
needs a `ServersTransport` object, which the chart does not create:

```yaml
services:
  server:
    annotations:
      traefik.ingress.kubernetes.io/service.serversscheme: https
      traefik.ingress.kubernetes.io/service.serverstransport: myns-insecure@kubernetescrd
```

```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: insecure
  namespace: myns
spec:
  insecureSkipVerify: true
```

Leave `HTTPS: 0` if you would rather have the ingress controller terminate TLS
and talk plain HTTP inside the cluster, which is what most people want.

## Tuning the bundled MySQL

`mysql.config` is the `my.cnf` the chart mounts. It defaults to a bare
`[mysqld]` header, which is what the chart has always mounted:

```yaml
mysql:
  enabled: true
  config: |
    [mysqld]
    max_allowed_packet = 64M
    character-set-server = utf8mb4
    collation-server = utf8mb4_unicode_ci
    innodb_buffer_pool_size = 512M
```

It is mounted over `/etc/mysql/my.cnf`, which replaces the file the image ships
rather than adding to it. On the official image that file is little more than an
`!includedir` pointing at `/etc/mysql/conf.d`, so what you give up is the
ability to drop extra files in there, not any tuning of its own.

Changing it does not restart the pod by itself. A ConfigMap update is picked up
on the next restart, so roll the Deployment yourself or put a checksum in
`containers.mysql.podAnnotations` and let Helm do it.

One consequence worth knowing about if you ever open a shell in the MySQL pod:
because the image's own `my.cnf` is replaced, the socket path the `mysql` client
looks for and the one the server opens do not necessarily agree, and which way
it falls depends on the image underneath. Connect over TCP and it is the same
every time, which is how AnsibleForms connects and how the probes check:

```bash
kubectl exec deploy/<release>-mysql -- \
  mysql -h 127.0.0.1 --protocol=TCP -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"
```

### Health checks

MySQL gets a startup, a readiness and a liveness probe, all running
`mysqladmin ping`, all configurable under `containers.mysql`:

```yaml
containers:
  mysql:
    startup:
      enabled: true
      failureThreshold: 30   # x periodSeconds is the budget for a first boot
    readiness:
      enabled: true
    liveness:
      # Set to false if you would rather nothing ever restarted the database
      enabled: true
```

The liveness probe is deliberately slack, 90 seconds of silence before it acts,
because restarting a database that was merely busy is worse than leaving it
alone. The startup probe holds the other two back while the data directory is
created and the init script runs.

The probe needs no credentials, and that is on purpose. `mysqladmin ping` exits
0 as soon as the server answers, and it answers "access denied" long before it
would answer a query, so the root password never has to appear on a command
line where every `ps` in the container could read it. Replace the command with
`containers.mysql.probeCommand` if you want something else.

## Where the pods run

`nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints` and
`priorityClassName` are available on both components and passed through exactly
as written, so anything Kubernetes accepts works. All empty by default.

```yaml
containers:
  server:
    nodeSelector:
      kubernetes.io/hostname: node-1
    tolerations:
      - key: workload
        operator: Equal
        value: apps
        effect: NoSchedule
    priorityClassName: high-priority
  mysql:
    # Usually the one that needs pinning, since it is the half owning a volume
    nodeSelector:
      kubernetes.io/hostname: node-1
    tolerations:
      - key: storage
        operator: Exists
        effect: NoSchedule
```

The chart creates no ServiceAccount and no PriorityClass. Name ones you manage
yourself with `containers.<component>.serviceAccountName` and
`priorityClassName`, otherwise the namespace's `default` ServiceAccount is used
and no priority class is set.

## Private registries

`imagePullSecrets` at the root covers both images:

```yaml
imagePullSecrets:
  - name: regcred
```

Override it per component when the two images live in different registries:

```yaml
containers:
  mysql:
    imagePullSecrets:
      - name: mysql-regcred
```

The Secrets have to exist in the release namespace already. The chart does not
create them:

```bash
kubectl -n <namespace> create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=... --docker-password=...
```

## Labelling everything

`commonLabels` and `commonAnnotations` go on every object the chart creates and
on both pods, for cost tags, ownership, Argo CD tracking, backup selectors and
so on:

```yaml
commonLabels:
  team: platform
  cost-center: "4711"

commonAnnotations:
  example.com/owner: platform@example.com
```

They deliberately never reach a Deployment's selector. A selector is immutable
once the Deployment exists, so a label added there could never be changed or
removed again, and an existing release would refuse to upgrade.

For labels on one pod only, use `containers.<component>.podLabels`, and
`podAnnotations` for annotations.

## Resource names

Everything the chart creates is named after the release:

| Resource | Name |
| --- | --- |
| Server Deployment, Service | `<release>-server` |
| MySQL Deployment, Service | `<release>-mysql` |
| MySQL ConfigMaps | `<release>-mysql-my-cnf`, `<release>-mysql-init` |
| Secret | `<release>-secrets` |
| PersistentVolumeClaims | `<release>-server-pvc`, `<release>-mysql-pvc` |
| Ingress | `<release>-ingress` |

Set `fullnameOverride` to use a different prefix, or `nameOverride` to change
the `app.kubernetes.io/name` label without touching the names.

To select the pods from outside the chart, use the component label rather than
the name label, which is the same for both:

```bash
kubectl logs -l app.kubernetes.io/component=server
kubectl logs -l app.kubernetes.io/component=database
```

## Configuration changes restart what reads them

A pod reads its configuration once, when it starts. Before 6.2.7 changing the
Secret left the running process with the environment it was given, and changing
`mysql.config` did not even reach the container: the file is mounted with
`subPath`, and subPath mounts are frozen at pod creation.

The chart writes a checksum of what it renders into the pod template, so a
change to either becomes an ordinary rollout. An upgrade that changes nothing
leaves the pods alone.

```yaml
rollOnChange:
  enabled: true    # the generated Secret and the MySQL my.cnf
  external: false  # an existingSecret, and the forms ConfigMaps
```

`external` is off by default because seeing those objects means reading them
from the cluster, and that returns nothing during `helm template`. Anything that
renders first and applies afterwards, Argo CD and Flux included, would get a
checksum that does not match the one an install produces. Turn it on if you run
Helm directly and want a `forms.yaml` change to restart the server on the next
upgrade.

## Checking an install

The chart ships a `helm test`:

```bash
helm test ansibleforms --namespace ansibleforms --logs
```

```
Asking http://ansibleforms-server.ansibleforms.svc.cluster.local:80/ for the front page
  HTTP 200
  the page is AnsibleForms
Connecting to ansibleforms-mysql:3306
  the database accepts connections (curl exit 1)
OK
```

It checks both halves on purpose. The front page is static, so the server
answers 200 quite happily with a database it cannot reach behind it, which is
the failure people actually run into. The test pod runs with the same security
context as the rest of the chart, so it works where the restricted Pod Security
Standard is enforced. `tests.enabled: false` turns it off.

## Values are validated

`values.schema.json` is checked by Helm on every render and every install, so a
mistake fails before anything reaches the cluster:

```
Error: values don't meet the specifications of the schema(s)
- at '/storages/mysql/accessMode': value must be one of 'ReadWriteOnce',
  'ReadOnlyMany', 'ReadWriteMany', 'ReadWriteOncePod'
```

The top level is closed, so a misspelling there is caught rather than silently
ignored:

```
- at '': additional properties 'stroages' not allowed
```

That also catches `mysql_deployment.enabled`, renamed to `mysql.enabled` in
6.2.1, which otherwise leaves you believing the database is disabled while the
chart deploys it anyway.

Below the top level the schema only checks types and enumerations, and lets
unknown keys through, so a values file carrying somebody's own leftover keeps
working across an upgrade.

## Keeping the database to itself

`networkPolicy.enabled` puts a policy on the bundled MySQL so that nothing can
open a connection to it except the AnsibleForms server of the same release:

```yaml
networkPolicy:
  enabled: true
  # Anything else that needs in, a backup job for instance
  mysqlExtraFrom: []
  # A policy for the server too. `from` is required: an ingress rule with no
  # peers allows nothing, and would cut the server off from your ingress
  # controller, so the chart refuses to render it empty.
  server:
    enabled: false
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
```

Off by default, and not only out of caution: NetworkPolicy is enforced by the
CNI, and several common ones, Flannel among them, do not enforce it at all.
A policy nothing enforces is worse than no policy, because it looks like
protection in `kubectl get netpol` and is not. Check your CNI before turning
this on and believing it.

Egress is left alone. The server has to reach whatever your playbooks talk to,
and guessing that list would break more than it protects.

## Pod Security Standards

The chart installs as it is into a namespace enforcing the **restricted** Pod
Security Standard, which is the strictest of the three and the default on
several managed distributions:

```bash
kubectl create namespace ansibleforms
kubectl label namespace ansibleforms \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
helm install ansibleforms ansibleforms/ansibleforms -n ansibleforms -f my_values.yaml
```

Both pods run as a pinned non-root user, the server as 1000 and MySQL as 999,
with `seccompProfile: RuntimeDefault`, every capability dropped and privilege
escalation refused. The server keeps `NET_BIND_SERVICE` and the
`net.ipv4.ip_unprivileged_port_start` sysctl, both of which restricted permits,
which is how it goes on listening on port 80 or 443.

There is no init container. Earlier versions shipped one that ran as **root**
purely to `chown` the server's volume;
`containers.server.podSecurityContext.fsGroup` asks the kubelet to do that
instead, which is cheaper and is the only form restricted accepts.

### If your storage ignores fsGroup

NFS with `root_squash` is the usual case. Clear both security contexts and put
the init container back:

```yaml
containers:
  server:
    podSecurityContext: null
    securityContext: null
    initContainers:
      - name: prepare-persistent-volume
        image: ansibleguy/ansibleforms:6.2.1
        command: ["sh", "-c", "chown -R 1000:1000 /app/dist/persistent"]
        securityContext:
          runAsUser: 0
        volumeMounts:
          - name: server-persistent-storage
            mountPath: /app/dist/persistent
  mysql:
    podSecurityContext: null
    securityContext: null
```

`null`, not `{}`. Helm merges your values file over the chart's own, so an empty
map leaves the defaults exactly where they were. And the two contexts go
together: clearing only the pod one sends MySQL back to starting as root and
stepping down with `setgid`, which the container context still forbids, and it
CrashLoops with `setgid: Operation not permitted`. The chart refuses to render
that combination rather than let you find out the hard way.

## Security Best Practices

- Prefer `secrets.existingSecret` over putting passwords in a values file
- Use `--set` or `--set-file` to hide secrets
- Consider using external secret management solutions (Vault, SOPS, etc.) for highly sensitive data

## Customization

### Basic 

- All environment variables can be set in `env:`.
- All resource limits, storage, and service types are configurable.
- Ingress can be enabled/disabled and fully customized.
- Storage can be backed by dynamic StorageClasses or static PVs as needed.
- Forms configuration (`forms.yaml` and additional `forms/*.yaml`) and `custom.js` can be managed via ConfigMaps as shown above.

### Extras 1. Define extra volumes (root level) that you want to mount to containers.
```
extraVolumes:
  # ------------------------------------------------------------------------------
  # ADD HERE EXTRA VOLUME MOUNTS (if needed) (e.g CUSTOM CA CONFIGMAP or SECRET)
  # ------------------------------------------------------------------------------
  - name: ca-certs-configmap
    configMap:
      name: ca-certs-configmap
            
```

### Extras 2. Define extra volumes mounts that will be available to the server pod
```
containers:
  server:
    extraVolumeMounts:
      # ------------------------------------------------------------------
      # ENABLE THIS FOR CUSTOM CA CERTS (Must create configmap manually!)
      # ------------------------------------------------------------------
      - name: ca-certs-configmap
        mountPath: /etc/custom-certs/custom-ca.crt
        subPath: custom-ca.crt
        readOnly: true
            
```
### Extras 3. Define one or more init containers (e.g for changing the ownership of the specified directory)
```
containers:
  server:
    initContainers:
      - name: prepare-persistent-volume
        image: ansibleguy/ansibleforms:6.1.3-rc
        imagePullPolicy: IfNotPresent
        # This command changes the ownership of the specified directory.
        command: ["sh", "-c", "chown -R 1000:1000 /app/dist/persistent"]
        securityContext:
          # The container must run as the root user to have permission to chown.
          runAsUser: 0
        volumeMounts:
          - name: server-persistent-storage
            mountPath: /app/dist/persistent
```
### Extras 4. Configure extra environment variables
```
applications:
  server:
    env:
    # ******** UNCOMMENT TO IGNORE PRIVATE CA CERTS ********
    # NODE_TLS_REJECT_UNAUTHORIZED: 0

    # ******** UNCOMMENT THIS FOR PRIVATE CA CERTS ********
    # NODE_EXTRA_CA_CERTS: /etc/custom-certs/custom-ca.crt
```


### Extras 5. Other possible settings (other applications)
```
applications:
  mysql:
    password: <ENTER_PASSWORD_HERE>
    user: root
    # host: "mysql"   -> Setup custom mysql
    # port: "3306"    -> Setup custom mysql port
```


### Extras 5. Server Liveness and Readiness
#### Note: In case you face readiness issues or 503 Server errors after long api requests + big latency queries then increase the timeout value below.
```

containers:
  server:
    liveness:
      path: /
      initialDelaySeconds: 15
      periodSeconds: 15
      timeoutSeconds: 15
    readiness:
      path: /
      initialDelaySeconds: 15
      periodSeconds: 15
      timeoutSeconds: 15

```


## Notes

- Pods and Services are discoverable by their service name within the namespace.
  See [Resource names](#resource-names) for what those names are.
- For a full list of environment variables and their meanings, see the comments in `values.yaml` or visit the AnsibleForms documentation.
