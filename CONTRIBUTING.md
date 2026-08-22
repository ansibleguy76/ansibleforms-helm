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

`ci/*-values.yaml` are the scenarios CI actually installs on a kind cluster.
`test/values/*-values.yaml` are render-only scenarios, for combinations that
cannot be installed unattended, such as HTTPS mode, which needs port 443 and a
capability the pod security context drops.

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

`version` is the chart version and follows the chart's own changes. `appVersion`
tracks the AnsibleForms release the default image points at. They are no longer
kept in lockstep: a fix to a template does not need a new application release.

Anything that renames a resource, removes a value or forces an existing
Deployment to be recreated is a major bump, and belongs in `CHANGELOG.md` with
the steps an operator has to take.

## Repository settings this depends on

The release workflow needs no secrets, the automatic `GITHUB_TOKEN` covers both
the GitHub release and the push to GHCR. Two things are owner-only, though:

- **Settings > Pages**, source set to *GitHub Actions*, for the Helm repository.
- The **package visibility** on the GHCR package, which GitHub creates private.
  It can only be changed after the first push, from the package page.
