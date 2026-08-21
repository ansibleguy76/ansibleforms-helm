# Changelog

## 6.2.0

First release with continuous integration and an automated publish. Nothing was
renamed and no value was removed, so an existing release upgrades in place.

### Fixed

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
