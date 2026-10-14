# ${{ .Inputs.serviceName }}

${{ .Inputs.description }}

A hello-world web page in a container on Azure Container Apps. The image lives
in your environment's shared Azure Container Registry and is pulled by the
Container App's own identity, so no registry password or credential exists
anywhere.

## Change the greeting

Edit one line in `Dockerfile`:

```dockerfile
ENV GREETING="Hello from Wayfinder"
```

Open a pull request and the preview shows the new text.

## The delivery pipeline

| When | What happens |
| --- | --- |
| A pull request opens or updates | `wf deploy --dry-run`, then the image is built and pushed to the develop registry as `pr-<number>-<sha7>` and a preview instance `${{ .Inputs.serviceName }}-pr<number>` (its own Container App) is deployed to the develop environment. Its URL is posted as a new pull request comment, a job annotation and the job summary on every deploy |
| The pull request closes | The preview instance is destroyed. The shared registry and its images stay |
| A merge to `main` | The image is built as `sha-<sha7>` and `${{ .Inputs.serviceName }}-develop` is updated to it |
| A `v*` tag is pushed | Nothing is built: the image `sha-<sha7>` already built for that commit is imported from the develop registry into the production registry, tagged with the release, and `${{ .Inputs.serviceName }}-prod` is updated to it. A tag on a commit never built for develop fails with a clear error |

The page shows `release <RELEASE>`, read at container start from `APP_RELEASE`,
so a promoted image (same digest as develop's) shows its production release.

## The stack

```
pushimage -> app -> smoke
```

- **pushimage** runs `.wayfinder/ensure-image.sh` on the machine running the
  deploy, signed in to Azure as the environment's own identity. It skips work
  when the tag is already in the registry (`FORCE_BUILD=1` builds anyway).
- **app** is the Container App, created in the environment's resource group
  with `min_replicas = 0`.
- **smoke** fetches the public URL, retrying for at most five minutes while the
  new revision starts, and fails the deploy if the page does not answer.

## What CI needs

Nothing to set up by hand. Creating this repository made two GitHub
environments, `develop` (merges and pull request previews) and `production`
(tags), each with its own Wayfinder service account trusted only by a job that
declares that environment, and these variables:

| Variable | Set on | |
| --- | --- | --- |
| `WAYFINDER_SERVER` | The repository | Your Wayfinder API URL |
| `WF_REGION` | The repository | The Azure region, e.g. `uksouth` |
| `WAYFINDER_SERVICE_ACCOUNT` | Each environment | The account that job signs in as |
| `WAYFINDER_ENVIRONMENT` | Each environment | The Wayfinder environment that job deploys to |

Optional: `WF_IDENTITY` overrides the Azure identity deployments use, which is
otherwise `<workspace>/<environment>/azure-<environment>`.

The registry addresses come from Wayfinder environment variables that team
onboarding set (`acrLoginServer`, `acrId`, and in production
`acrPromoteFromId`/`acrPromoteFromLoginServer`), not from this repository.

## Deploying it yourself

You need the `az` CLI and `curl`, plus `docker` when the image for your
`RELEASE` is not in the registry yet.

```bash
wf up -f Wayfinder.yaml -i ${{ .Inputs.serviceName }}-dev \
  -w <workspace> -e <environment> \
  --identity <workspace>/<environment>/azure-<environment> --region ${{ .Inputs.region }} \
  --env-var RELEASE=$(git describe --always --dirty)
```

Tear it down with `wf down -i ${{ .Inputs.serviceName }}-dev -e <environment>`.
