# Contributing

## Running the checks locally

Everything CI does can be run before pushing:

```bash
pip install yamllint
yamllint --strict .
helm lint . --strict

for f in ci/*-values.yaml test/values/*-values.yaml; do
  helm lint . --strict --values "$f"
  helm template ansibleforms . --values "$f" | kubeconform -strict -summary
done
```

`ci/*-values.yaml` are the scenarios `ct` installs on a kind cluster.
`test/values/*-values.yaml` are mostly render-only, for combinations that cannot
be installed unattended or that only exist to prove a manifest is shaped right.
Some of them are driven by hand from the workflow: the two `ingress-*` files are
installed behind a real controller, and `minimal-mysql` exists to prove the
chart still renders with its values cleared.

## What CI checks

Four jobs, three of which need a cluster:

**Lint and render.** yamllint, `helm lint` on every values file, and `helm
template` plus `kubeconform -strict` across three Kubernetes versions. On top of
that a few assertions that rendering alone would not make:

- the chart refuses to write the placeholder credentials into a real Secret
- every Ingress backend resolves to a port its Service actually publishes,
  followed the way a controller would follow it
- every scheduling value comes out in the pod spec unchanged, `commonLabels` and
  `commonAnnotations` reach every object, and neither reaches a selector, which
  is immutable
- the MySQL probes exist and none of them carries a credential
- the chart version moved, if anything under `Chart.yaml`, `values.yaml`,
  `templates/` or `files/` did
- the two security context combinations that cannot work are still refused, and
  the message still names the value to change

`values.schema.json` is checked by Helm itself on every render and every
install, so a wrong type or a misspelled top level key fails before anything
reaches a cluster. It is deliberately strict at the top level and permissive
below it: a misspelling at the top is silent and sometimes dangerous, while a
stray key further down is usually someone's own leftover and should not block
their upgrade.

**Install on kind.** `ct install` for the `ci/` scenarios, which also runs
`helm test` after each one, plus the cases a values file alone cannot describe:
a Secret managed outside the chart, a database the chart does not manage, two
releases side by side in one namespace, and an install into a namespace
enforcing the restricted Pod Security Standard.

**Upgrade a live release.** Installs the newest published chart, writes a row
into the database and a file onto the server's volume, upgrades to the branch,
and checks that every claim still points at the same volume and that both
markers are still there. This is the one that catches a renamed
PersistentVolumeClaim, which every other check in the file would happily let
through: a renamed claim is an empty volume with the old one deleted underneath
it.

**Route through a real ingress controller.** kind ships without one, so the
Ingress used to be rendered, validated and never asked for a single page. This
installs ingress-nginx and fetches the application through it, both plain and
with the application terminating TLS itself. That second case is where the port
bug fixed in 6.2.2 lived: a manifest that validates perfectly and that no
controller can route.

To try a real install:

```bash
helm upgrade --install test . \
  --namespace ansibleforms-test --create-namespace \
  --values ci/default-values.yaml --wait
```

## Cutting a release

Releases are driven by the `version` field in `Chart.yaml`. Bump it in a pull
request, merge to `main`, and the release workflow tags the version, attaches
the packaged chart to a GitHub release, pushes it to GHCR as an OCI artifact and
rebuilds the Helm repository index published on GitHub Pages.

It runs after CI, not alongside it, and does nothing unless CI finished green,
so a failing build cannot publish. Merging with a version that already has a tag
is a no-op, which is what makes it safe to leave running on every push. To
rebuild the Helm repository index without releasing anything, run the workflow
by hand from the Actions tab.

`version` is the chart version and follows the chart's own changes. `appVersion`
tracks the AnsibleForms release the default image points at. They are no longer
kept in lockstep: a fix to a template does not need a new application release.

Anything that renames a resource, removes a value or forces an existing
Deployment to be recreated is a major bump, and belongs in `CHANGELOG.md` with
the steps an operator has to take.

CI refuses a pull request that changes `Chart.yaml`, `values.yaml`, `templates/`
or `files/` without moving the version, and refuses a version that has already
been released. Both would merge green and publish nothing, leaving the change on
`main` until some later release dragged it along. Changes that do not reach the
packaged chart, to CI, to `test/` or to the documentation, need no bump; `ci/`
and `test/` are in `.helmignore`.

## Repository settings this depends on

The release workflow needs no secrets, the automatic `GITHUB_TOKEN` covers both
the GitHub release and the push to GHCR.

One thing is owner-only: **Settings > Pages**, source set to *GitHub Actions*.
Without it the Helm repository is not published; the release and the OCI
artifact still are, and the workflow says so in its run summary rather than
failing. Enabling Pages from the workflow itself does not work, creating the
site needs repository administration rights that the automatic token does not
have, whatever permissions the job requests.

The GHCR package needs nothing. Pushed from Actions it is linked to the
repository and inherits its visibility, so on a public repository it can be
pulled anonymously right after the first release.
