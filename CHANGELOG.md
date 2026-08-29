# Changelog

## 6.2.6

Three things a published chart is expected to have and this one did not: a
values schema, a NOTES output, and a test.

### Added

- **`values.schema.json`.** Helm checks it on every render and every install, so
  a wrong type or a misspelled key fails before anything reaches a cluster
  rather than showing up as a puzzling manifest later.

  It is strict at the top level and permissive below it, on purpose. A
  misspelling at the top is silent and sometimes dangerous: `stroages:` simply
  does nothing, and `mysql_deployment.enabled`, which was renamed in 6.2.1,
  leaves you believing the database is disabled while the chart deploys it
  anyway. Both are now refused by name. Further down, a stray key is usually
  somebody's own leftover and blocking their upgrade over it would be rude, so
  only types and enumerations are checked there.

  `global` is allowed, since Helm puts it in every chart's values whether or not
  anything reads it.

- **`templates/NOTES.txt`.** After an install it prints the URL, or the
  `port-forward` to reach a ClusterIP, or where to watch for a LoadBalancer
  address; the admin username and the command to read the password out of the
  Secret rather than the password itself; and a reminder that credentials taken
  from a values file also sit in the release history Helm keeps in the cluster.
  It says so when `ingress.hostname` is still the placeholder, when HTTPS mode
  needs the ingress controller told to speak TLS to the backend, and when
  `mysql.enabled` is false and the schema has to be applied by hand.

- **`helm test`.** A pod that fetches the front page through the Service and
  checks what came back really is AnsibleForms, then opens a connection to the
  database. Both halves matter: the front page is static, so the server answers
  200 perfectly happily with a database it cannot reach behind it, which is the
  failure people actually hit. Verified by scaling MySQL to zero, where the page
  still returns 200 and the test fails on the database.

  The test pod carries the same security context as the rest of the chart, so it
  is accepted where the restricted Pod Security Standard is enforced. Its
  delete policy is `before-hook-creation` alone: adding `hook-succeeded` removes
  the pod the moment it passes and `helm test --logs` then fails with "pods not
  found" on a run that worked.

  Turn it off with `tests.enabled: false`. `ct install` runs it in CI after
  every install, and CI also runs it inside the restricted namespace.

## 6.2.5

The chart could not be installed at all in a namespace enforcing the restricted
Pod Security Standard, which several managed distributions turn on by default.
It can now, and does so out of the box.

This changes how both pods run. Read the upgrade note before running it.

### Changed

- **Both pods run as a non-root user, pinned.** The server as 1000 and MySQL as
  999, with `seccompProfile: RuntimeDefault`, every capability dropped, and
  privilege escalation refused. MySQL had no security context of any kind
  before.

- **The root init container is gone.** `prepare-persistent-volume` existed only
  to `chown -R 1000:1000` the server's volume, and ran as root to do it, which
  the restricted standard forbids outright.
  `containers.server.podSecurityContext.fsGroup` asks the kubelet to take
  ownership instead. That is cheaper, since `fsGroupChangePolicy:
  OnRootMismatch` skips the pass entirely when the top of the volume already
  looks right, and it removes a privileged container from every install.

### Added

- **`containers.server.podSecurityContext` and `containers.mysql.podSecurityContext`,**
  carrying the defaults above. The sysctl that lets the application bind port 80
  or 443 is still added by the chart and is left alone if you write your own
  `sysctls`.

- **Two configurations the chart now refuses to render**, because both fail at
  runtime in a way that is very hard to trace back to a values file:

  - an init container running as root next to `runAsNonRoot: true`. The kubelet
    rejects it with `container's runAsUser breaks non-root policy` and the pod
    sits in `Init:CreateContainerConfigError` while Helm reports the release as
    deployed.
  - a cleared pod security context with the container one left in place. MySQL
    goes back to starting as root and stepping down with `setgid`, which the
    dropped capabilities forbid, and it dies with `setgid: Operation not
    permitted` on a loop.

  Both now stop at `helm template` with a message naming the value to change.

### Upgrading

Nothing to do for most people. Upgrading an existing release was checked against
one holding real data: both claims kept their volume, the rows and the generated
SSH key survived, and the kubelet moved the volume ownership from `root` to the
right group on the way through.

Two cases need attention:

- **You keep your own copy of `values.yaml`.** It still contains the
  `prepare-persistent-volume` init container, and that combination is refused.
  Delete it from your values; `fsGroup` does its job now.

- **Your storage ignores `fsGroup`.** NFS with `root_squash` is the usual case.
  Set both `containers.<component>.podSecurityContext` and
  `containers.<component>.securityContext` to `null` and put the init container
  back. It has to be `null` rather than `{}`: Helm merges your values over the
  chart's own, and an empty map changes nothing. The release is then not
  installable where restricted is enforced, which is the trade.

## 6.2.4

The MySQL half of the chart brought up to the standard of the server half. It
had no health checks of any kind, no way to tune the database, and a render
that fell over if you cleared its resources. Everything here is additive and
the defaults render what 6.2.3 rendered, except for the three new probes.

### Added

- **Health checks for MySQL.** A startup probe, a readiness probe and a
  liveness probe, all running `mysqladmin ping`. Without a readiness probe the
  Service advertised a ready endpoint the moment the container started, while
  MySQL was still refusing connections: measured on an empty data directory
  that window is about ten seconds, and it grows with the size of the volume.
  It does not make AnsibleForms start any sooner, since it retries either way.
  What changes is that readiness stops lying, so `helm --wait`, Argo CD health
  and anything else treating the database as a dependency work from something
  true.

  The liveness probe is deliberately slack, 90 seconds of silence before it
  acts, because restarting a database that was merely busy is worse than leaving
  it alone. Set `containers.mysql.liveness.enabled` to false if you would rather
  nothing ever restarted it. The startup probe holds the other two back for up
  to 300 seconds while the data directory is created and the init script runs.

  The probe needs no credentials. `mysqladmin ping` exits 0 as soon as the
  server answers, and it answers "access denied" long before it would answer a
  query, so the root password never reaches a command line where every `ps` in
  the container could read it. A plain TCP check would not do: while the data
  directory is being built the entrypoint runs a temporary server on a socket
  with networking off, so a port check calls MySQL ready long before it is.
  Override the whole thing with `containers.mysql.probeCommand`.

- **`mysql.config`.** The `my.cnf` the chart mounts was a bare `[mysqld]` header
  with nothing under it and no way to change it, so tuning the bundled database
  meant forking the chart. The default is still that same empty header.

  It is mounted over `/etc/mysql/my.cnf`, replacing the file the image ships
  rather than adding to it. On the official image that file is little more than
  an `!includedir` pointing at `/etc/mysql/conf.d`, so what is given up is the
  ability to drop extra files in there, not any tuning of its own.

- **The extras the server already had**, now on MySQL too: `extraEnv`,
  `extraEnvFrom`, `extraVolumes`, `extraVolumeMounts`, `imagePullPolicy`,
  `securityContext` and `podSecurityContext`. The security contexts are empty by
  default: the official image starts as root and steps down to the mysql user
  once it has taken ownership of the data directory, so forcing `runAsNonRoot`
  breaks a first boot.

### Fixed

- **Clearing the MySQL resources no longer fails the render.** The template
  reached straight into `containers.mysql.resources.limits.cpu`, so
  `--set containers.mysql.resources=null` or a values file that nulls the block
  died with `nil pointer evaluating interface {}.limits` instead of falling back
  to a default. Every value the MySQL template reads now goes through a default,
  which is how the server template already worked.

## 6.2.3

Where the pods are allowed to run, and how to label everything the chart
creates. All of it is additive and every default is empty, so an existing
release upgrades with no change to what it renders.

### Added

- **Scheduling, on both components.** `nodeSelector`, `tolerations`, `affinity`,
  `topologySpreadConstraints` and `priorityClassName` under
  `containers.server` and `containers.mysql`. Passed through as written, so
  anything Kubernetes accepts works here. The database is usually the half that
  needs pinning, since it is the one that owns a volume.
- **`imagePullSecrets`,** at the root for both images, and per component under
  `containers.server` and `containers.mysql` when the two live in different
  registries. Without this the chart could not be used from a private registry
  or a mirror at all. The Secrets have to exist already, the chart does not
  create them.
- **`commonLabels` and `commonAnnotations`,** added to every object the chart
  creates and to both pods. For cost tags, ownership, Argo CD tracking, backup
  selectors and the like. They never reach a Deployment's selector, which is
  immutable: a label added there could not be changed or removed afterwards, and
  an existing release would fail to upgrade outright.
- **`podLabels`,** on both components, next to the `podAnnotations` the server
  already had. `podAnnotations` now exists for MySQL too.
- **`serviceAccountName` for MySQL,** and the server's is documented in
  `values.yaml` at last. The chart still creates no ServiceAccount, it only uses
  one you name.

### Notes

`serviceAccountName` was already read from the values by the server template but
never appeared in `values.yaml`, so nobody could reasonably have known it was
there.

CI gains a check that every scheduling field in a values file comes out in the
pod spec unchanged, that `commonLabels` and `commonAnnotations` reach every
object, and that neither reaches a selector. Rendering already rejected a block
indented into the wrong parent, since the stray keys show up to `kubeconform`
as `additionalProperties`, but nothing caught a field the template simply never
referenced.

## 6.2.2

Two bugs, both of which stop the chart working in situations people actually
hit. Nothing is added and no default changes, but four resources are renamed,
so read the upgrade note below before running it.

### Fixed

- **Turning on HTTPS broke the Ingress.** Setting
  `applications.server.env.HTTPS: 1` moves the application and its Service to
  443, but the Ingress backend said port 80 no matter what. The result was an
  Ingress pointing at a port its Service did not publish: ingress-nginx answers
  503, Traefik logs `Cannot create service: service port not found` and drops
  the route to a 404. The application itself was healthy the whole time, which
  is what made it so confusing to debug. The container port, the Service port
  and the three probes are now a single named port, and the Ingress backend
  refers to it by name, so the three cannot disagree again. CI resolves the
  Ingress backend the way a controller does and fails if it does not land on a
  port the Service publishes.

- **Two releases in the same namespace fought over each other.** The
  Deployments, Services and ConfigMaps were named with plain literals: `server`,
  `mysql`, `mysql-my-cnf` and `mysql-init-script`. Installing a second release
  beside the first fails outright under Helm, which refuses to adopt resources
  another release owns. Rendered with `helm template` and applied, which is how
  Argo CD and Flux deploy it, nothing stops it at all: the second release
  silently overwrites the first's Deployments and Services, and the first
  release's PersistentVolumeClaims are left bound, paid for and mounted by
  nothing. On top of that both Services selected `app.kubernetes.io/name:
  server`, identical across releases, so each Service could route to the other
  one's pods. Every resource is now named after the release and the selectors
  carry the instance, so releases are independent.

- **Labels were copied by hand into eight templates and had drifted.** The PVCs
  claimed `app.kubernetes.io/instance: server`, the Services claimed
  `instance: mysql`, `part-of` held the release name rather than the
  application, and only the server Deployment carried `managed-by` and
  `version`. They come from one helper now and follow the standard meaning, so
  `app.kubernetes.io/instance` is the release and `app.kubernetes.io/component`
  is what tells the server and the database apart.

### Added

- **`services.server.annotations` and `services.mysql.annotations`.** Needed to
  make HTTPS usable end to end: Traefik reads its `service.*` settings from the
  Service, not from the Ingress, and that is where you tell it to speak TLS to
  the backend. There was no way to put an annotation on either Service before.
- **`nameOverride` and `fullnameOverride`,** the usual pair, for when the
  release name is not the prefix you want.

### Upgrading

Four resources are renamed: `server`, `mysql`, `mysql-my-cnf` and
`mysql-init-script` become `<release>-server`, `<release>-mysql`,
`<release>-mysql-my-cnf` and `<release>-mysql-init`. Helm creates the new ones
and removes the old, which rolls both pods once.

**No storage is touched.** The Secret, the Ingress and both PersistentVolumeClaims
keep the names they have always had, which is why the prefix is the release name
rather than the `<release>-<chart>` a scaffolded chart would use. Renaming a PVC
does not move a volume, it provisions an empty one and deletes the old, so those
names were left exactly as they were. The upgrade was run against a release
holding real data to confirm it: same claims, same volumes, database rows and
the generated SSH key all still there afterwards.

Two things to know:

- `applications.mysql.host` now defaults to `<release>-mysql` instead of the
  literal `mysql`. If you run your own database and relied on the old default
  resolving to something you deployed yourself, set the value explicitly.
- Anything outside the chart that selects on `app.kubernetes.io/name: server` or
  `name: mysql` needs updating to `app.kubernetes.io/component: server` or
  `component: database`. That covers NetworkPolicies, ServiceMonitors and
  scripts that do `kubectl logs deployment/server`.

## 6.2.1

Three ways of running AnsibleForms that the chart could not express before.
Everything is additive and every default is unchanged, so an existing release
upgrades in place.

### Added

- **`secrets.existingSecret`.** Point it at a Secret you manage yourself and the
  chart creates none, so credentials can come from External Secrets, Sealed
  Secrets, SOPS or anything else without ever passing through `values.yaml`. The
  Secret must hold `DB_USER`, `DB_PASSWORD`, `ENCRYPTION_SECRET`,
  `ADMIN_USERNAME` and `ADMIN_PASSWORD`.
- **`mysql.enabled`.** Set it to false and the chart deploys no database at all,
  so AnsibleForms can talk to a server you already run: point
  `applications.mysql.host` and `.port` at it. The Deployment, Service, PVC and
  both ConfigMaps are skipped. Based on the work of @HrBingR in #6, with the
  value renamed from `mysql_deployment.enabled` to match the rest of the chart.
  **Careful on an existing release: disabling this removes the MySQL PVC, and
  with a reclaim policy of Delete the data goes with it. Take a dump first.**
- **`containers.server.extraEnv` and `containers.server.extraEnvFrom`,** for
  environment `applications.server.env` cannot express: values from another
  Secret or ConfigMap, from the downward API, or whole ConfigMaps and Secrets
  injected at once.
- **`files/schema.sql`.** The base schema used to be embedded in the MySQL init
  ConfigMap, where only the bundled database could ever see it. It is now a file
  the ConfigMap includes, so the same statements can be applied to a database
  the chart does not manage. It no longer drops anything, creates each table
  only if missing and grants nothing, so it is safe to run against a server that
  already holds data. Running AnsibleForms on your own database needs this
  applied once: the application migrates an existing schema forward but does not
  create one, and without it the pod starts, passes its probes and serves the
  static front page while every query behind it fails.

### Fixed

- **The chart no longer writes the placeholder credentials from `values.yaml`
  into a real Secret.** It refuses to render and says how to fix it. This was
  worse than it sounds: the generated Secret is called `<release>-secrets`,
  which is exactly what most people name the one they manage themselves, so a
  sync could quietly replace live credentials with `<ENTER_PASSWORD_HERE>`. The
  symptom looks like a database problem rather than a configuration one.
- Disabling MySQL no longer leaves a stray `---` at the end of `service.yaml`,
  and the templates end with a newline.

### Note for anyone rendering the chart with defaults only

`helm template` and `helm lint` with no values now fail on purpose, because the
shipped credentials are placeholders. Pass a values file, or set
`secrets.existingSecret`.

## 6.2.0

First release with continuous integration and an automated publish. Nothing was
renamed and no value was removed, so an existing release upgrades in place.

### Fixed

- **The server could not bind its port on a stock cluster.** It listens on 80 or
  443, both privileged, as an unprivileged user, and a pod network namespace
  always starts with `net.ipv4.ip_unprivileged_port_start` at 1024 regardless of
  the node setting. The process died with
  `listen EACCES: permission denied 0.0.0.0:80` and the pod never came up. It
  happened to work wherever something else had already lowered that sysctl,
  which is why it went unnoticed. The chart now sets the sysctl itself, which is
  on the kubelet's safe list; `containers.server.bindPrivilegedPorts: false`
  turns it off. Note that adding `NET_BIND_SERVICE` does not fix this: the
  process is already non-root at exec, so the capability never reaches its
  effective set.
- `HTTPS: 1` no longer breaks the render. The value is documented as `0`/`1` and
  people write it unquoted, which YAML reads as a number, while the template ran
  it through `atoi`, which only accepts strings. Only the quoted `"1"` used to
  work.
- `services.server.type: LoadBalancer` no longer breaks the render when no fixed
  address is given, which is the normal case with MetalLB or a cloud controller.
  The template dereferenced `loadbalancer.ip` without checking the parent key
  existed.
- `containers.server.strategy` accepts the Kubernetes shape (`{type: Recreate}`)
  as well as a plain string. The map form used to render as
  `type: map[type:Recreate]`, which the API server rejects.
- `templates/mysql-pv-claim.yaml` held two half-merged copies of the same PVC in
  one document. YAML kept the last of each duplicated key, so the file happened
  to produce a valid claim, but the first copy was dead weight and the mistake
  was invisible.
- Removed `templates/namespace.yaml`, which was an empty file.
- The README examples used `application`, `storage`, `service` and `container`
  where the chart expects `applications`, `storages`, `services` and
  `containers`. Copying an example configured nothing and silently left the
  placeholder defaults in place.

### Changed

- Added a `startupProbe`, enabled by default with a 300 second budget. On a
  fresh install the database migrations can outlast the liveness probe, and the
  kubelet then restarts a pod that was making perfectly good progress. Tune it
  under `containers.server.startup`, or set `enabled: false` to drop it.
- `stdin` and `tty` now default to `false`. A server process has no use for a
  terminal.
- The default MySQL image is pinned to `mysql:8.4` instead of `mysql:latest`. A
  floating tag means an unattended major upgrade whenever the pod is
  rescheduled, and MySQL does not support downgrades, so a rollback leaves the
  data directory unreadable. **Already running a 9.x image? Set
  `containers.mysql.image` to your current tag before upgrading this chart.**
- `appVersion` is set for the first time, and the default application image
  moved from `6.1.3-rc` to the released `6.2.1`. Chart version and application
  version are tracked separately from now on.
- Standard `app.kubernetes.io` labels on the server Deployment and both
  Services. Selectors were left untouched, since they are immutable on an
  existing object.

### Added

- `containers.server.podAnnotations`, for a checksum annotation or anything else
  that should trigger a rollout.
- `storages.<component>.accessMode`, still `ReadWriteMany` by default. Plenty of
  storage classes only offer `ReadWriteOnce`, and with a single replica that is
  perfectly fine.
- `failureThreshold` on the liveness and readiness probes.
- CI on every pull request: `yamllint`, `helm lint`, and a render of six value
  scenarios against three Kubernetes versions checked with `kubeconform`, plus a
  real install on kind. All four bugs above were found by writing it.
- Releases are published automatically from `Chart.yaml`, as a GitHub release, an
  OCI artifact on GHCR and a Helm repository on GitHub Pages.
