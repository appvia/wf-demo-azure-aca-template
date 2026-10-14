#!/usr/bin/env bash
#
# Puts one release's container image in the environment's shared Azure
# Container Registry, doing as little as it can to get there.
#
#   usage: .wayfinder/ensure-image.sh <login-server> <repository> <release> \
#            [<promote-from-registry-id> <promote-from-login-server>]
#
# The stack's `pushimage` component calls this with the environment's Azure
# identity (Wayfinder projects ARM_CLIENT_ID, ARM_TENANT_ID,
# ARM_SUBSCRIPTION_ID and the federated token file ARM_OIDC_TOKEN_FILE_PATH).
#
#   Already there   When <repository>:<release> is in the registry this exits
#                   before docker is mentioned. FORCE_BUILD=1 builds anyway.
#   Build mode      No promote-from registry (develop and previews): docker
#                   build and push.
#   Promote mode    A promote-from registry is given (production): never
#                   builds. Imports PROMOTE_SOURCE_TAG (sha-<commit>, exported
#                   by the production workflow) from that registry, tags it
#                   <release>, and checks both digests match. A release whose
#                   commit was never built for develop fails.
set -euo pipefail

usage="usage: ensure-image.sh <login-server> <repository> <release> [<promote-from-registry-id> <promote-from-login-server>]"
login_server="${1:?${usage}}"
repository="${2:?${usage}}"
release="${3:?${usage}}"
promote_from_id="${4:-}"
promote_from_login_server="${5:-}"

registry="${login_server%%.*}"

for var in ARM_CLIENT_ID ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_OIDC_TOKEN_FILE_PATH; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::ensure-image: ${var} is not set. Run this as the stack's pushimage component (withAccess: cloud), which projects the environment's Azure identity." >&2
    exit 1
  fi
done
if [[ ! -r "${ARM_OIDC_TOKEN_FILE_PATH}" ]]; then
  echo "::error::ensure-image: federated token file ${ARM_OIDC_TOKEN_FILE_PATH} is not readable." >&2
  exit 1
fi

# Wayfinder hands over the identity but does not log the az CLI in. Log in to a
# private config directory so no session of the machine's own user is used or
# changed.
AZURE_CONFIG_DIR="$(mktemp -d)"
export AZURE_CONFIG_DIR
trap 'rm -rf "${AZURE_CONFIG_DIR}"' EXIT
az login --service-principal \
  -u "${ARM_CLIENT_ID}" \
  -t "${ARM_TENANT_ID}" \
  --federated-token "$(cat "${ARM_OIDC_TOKEN_FILE_PATH}")" \
  --allow-no-subscriptions >/dev/null
az account set -s "${ARM_SUBSCRIPTION_ID}"
echo "ensure-image: signed in to Azure as $(az account show --query user.name -o tsv)"

# Sets found_digest to the digest of <registry> <repository>:<tag>, or to ""
# when the tag is not there. Decided by az's exit status, not its output:
#   exit 0 + sha256:<64 hex>                         -> present
#   exit 3 + "the specified tag does not exist"      -> absent (az 2.90 says this
#                                                      for a missing tag and a
#                                                      missing repository alike)
#   anything else (auth, network, odd output)        -> fail the deploy
# Runs in this shell, not a $(...) subshell, so `exit` stops the script.
lookup_err="${AZURE_CONFIG_DIR}/lookup.err"
found_digest=""
lookup_digest() {
  local out rc=0
  found_digest=""
  out="$(az acr repository show -n "$1" --image "$2:$3" --query digest -o tsv 2>"${lookup_err}")" || rc=$?
  if [[ ${rc} -eq 0 ]]; then
    if [[ "${out}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      found_digest="${out}"
      return 0
    fi
    echo "::error::ensure-image: looking up $1/$2:$3 succeeded but returned '${out}', not a sha256 digest." >&2
    exit 1
  fi
  if [[ ${rc} -eq 3 ]] && grep -q 'the specified tag does not exist' "${lookup_err}"; then
    return 0
  fi
  echo "::error::ensure-image: could not look up $1/$2:$3 (az exit ${rc}): $(cat "${lookup_err}")" >&2
  exit 1
}

lookup_digest "${registry}" "${repository}" "${release}"
existing="${found_digest}"
if [[ -n "${FORCE_BUILD:-}" ]]; then
  echo "ensure-image: FORCE_BUILD is set, replacing ${login_server}/${repository}:${release} whatever is there"
elif [[ -n "${existing}" ]]; then
  echo "ensure-image: ${login_server}/${repository}:${release} is already in the registry (${existing}), nothing to do"
  exit 0
fi

if [[ -n "${promote_from_id}" || -n "${promote_from_login_server}" ]]; then
  if [[ -z "${promote_from_id}" || -z "${promote_from_login_server}" ]]; then
    echo "::error::ensure-image: promote mode needs both the source registry id and login server (got id='${promote_from_id}' login server='${promote_from_login_server}')." >&2
    exit 1
  fi
  source_registry="${promote_from_login_server%%.*}"
  source_tag="${PROMOTE_SOURCE_TAG:-}"
  if [[ -z "${source_tag}" ]]; then
    echo "::error::Release tag must point at a commit already built for develop (missing ${promote_from_login_server}/${repository}:<unset PROMOTE_SOURCE_TAG>)" >&2
    exit 1
  fi
  lookup_digest "${source_registry}" "${repository}" "${source_tag}"
  source_digest="${found_digest}"
  if [[ -z "${source_digest}" ]]; then
    echo "::error::Release tag must point at a commit already built for develop (missing ${promote_from_login_server}/${repository}:${source_tag})" >&2
    exit 1
  fi

  echo "ensure-image: promoting ${promote_from_login_server}/${repository}:${source_tag} to ${login_server}/${repository}:${release} (no build)"
  # --force: the sha tag may already be here from an earlier release of the
  # same commit; it names the same digest, so overwriting it changes nothing.
  az acr import \
    --name "${registry}" \
    --source "${repository}:${source_tag}" \
    --registry "${promote_from_id}" \
    --image "${repository}:${release}" \
    --image "${repository}:${source_tag}" \
    --force

  lookup_digest "${registry}" "${repository}" "${release}"
  promoted_digest="${found_digest}"
  echo "ensure-image: source  ${promote_from_login_server}/${repository}:${source_tag} ${source_digest}"
  echo "ensure-image: release ${login_server}/${repository}:${release} ${promoted_digest}"
  if [[ "${promoted_digest}" != "${source_digest}" ]]; then
    echo "::error::ensure-image: promoted digest '${promoted_digest}' does not match source digest '${source_digest}'." >&2
    exit 1
  fi
  exit 0
fi

image="${login_server}/${repository}:${release}"
echo "ensure-image: building and pushing ${image}"
az acr login --name "${registry}"
docker build --platform linux/amd64 -t "${image}" .
docker push "${image}"
