# Azure Container App (hello world) template

A Wayfinder repository template (`aca-hello`). A repository created from it
holds a hello-world web page in a container, deployed to Azure Container Apps
from the Wayfinder environment's shared Azure Container Registry:

| When | What happens in the new repository |
| --- | --- |
| A pull request opens or updates | The image is built into the develop registry and a preview instance `<service>-pr<N>` is deployed to the develop environment; its URL is commented on the pull request |
| The pull request closes | The preview instance is destroyed (the registry and images stay) |
| A merge to `main` | `<service>-develop` is updated to the image built for that commit (`sha-<sha7>`) |
| A `v*` tag | That commit's image is imported into the production registry (no rebuild) and `<service>-prod` is updated to it |

Creating the repository also creates two GitHub environments, `develop` and
`production`, each with its own Wayfinder service account trusted only by that
repository's jobs declaring that environment, plus the variables the workflows
read. Nobody makes a credential, a federated credential or a role binding by
hand, and no secret is stored anywhere.
[`skeleton/README.md`](./skeleton/README.md) lists every variable.

## Layout

```
wf-demo-azure-aca-template/
├── wayfinder-template.yaml           Wayfinder reads this: inputs, service accounts, variables
└── skeleton/                         what gets copied into the new repository
    ├── Dockerfile                    nginx serving the page; ENV GREETING is the line to edit
    ├── docker/40-render-index.sh     writes the page at start from GREETING and APP_RELEASE (raw)
    ├── Wayfinder.yaml                the stack: pushimage -> app -> smoke
    ├── .wayfinder/ci.env             service name and wf CLI version (rendered)
    ├── .wayfinder/install-wf.sh      installs wf on the runner (raw)
    ├── .wayfinder/ensure-image.sh    builds/pushes (develop) or promotes (production) the image (raw)
    └── .github/workflows/            ci, wf-preview-teardown, wf-deploy-develop, wf-deploy-prod (raw)
```

The template is at the root of this repository, so the `RepoTemplate` leaves
`spec.path` empty.

## Inputs

| Input | Default | What it sets |
| --- | --- | --- |
| `serviceName` | required | Image repository and instance names; `^[a-z][a-z0-9-]{1,20}[a-z0-9]$` |
| `description` | empty | The README and the stack's description |
| `developEnvironment` | required | Wayfinder environment for previews and merges (GitHub environment `develop`) |
| `prodEnvironment` | required | Wayfinder environment for `v*` tags (GitHub environment `production`) |
| `region` | `uksouth` | The `WF_REGION` repository variable |

## Before the first deploy

The workspace's two environments must have been onboarded by the
`team-onboarding` workflow, which gives each of them:

- an Azure identity `<workspace>/<env>/azure-<env>` that owns the
  environment's resource group;
- a shared registry, deployed as the stack instance `registry`, published as
  the environment variables `azureResourceGroup`, `acrLoginServer` and `acrId`;
- in the production environment only, `acrPromoteFromId` and
  `acrPromoteFromLoginServer` naming the develop registry, which the
  production identity can read.

The catalogue plan `azure-container-app-acr@0.1.0` must be published.

## Use it

```bash
# 1. Register it (in this demo, Terraform does this as wayfinder_repo_template.aca_hello)
wf get repotemplate aca-hello -o yaml        # status.manifest is populated

# 2. Preview what it renders, creating nothing
wf create stack hello -w <workspace>
wf create coderepo hello -w <workspace> --from-template aca-hello --stack hello --dry-run \
  --no-input --input serviceName=hello --input developEnvironment=dev --input prodEnvironment=prod

# 3. Create the repository and apply its service accounts
wf create coderepo wf-demo-aca-hello -w <workspace> --from-template aca-hello --stack hello \
  --github-org <githuborg> --input serviceName=hello \
  --input developEnvironment=dev --input prodEnvironment=prod --apply-configuration
```
