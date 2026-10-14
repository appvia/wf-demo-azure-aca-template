#!/usr/bin/env bash
#
# Puts the `wf` CLI on the PATH of a GitHub-hosted runner.
#
#   usage: .wayfinder/install-wf.sh
#
# WF_CLI_VERSION in .wayfinder/ci.env picks the build. Leave it empty and CI
# tracks the latest development build, which is right while the platform itself
# is moving and wrong once it is not — pin a released version there when your
# deployments start mattering.
#
# The deploy jobs do NOT run inside the wftoolbox container image, and that is
# deliberate: this repository's stack builds its own container image and its own
# web bundle in LocalActions, which run on the machine driving the deploy. That
# machine therefore needs docker, make, go and node, which a GitHub-hosted
# ubuntu runner already has and the toolbox image does not.
set -euo pipefail

# shellcheck source=ci.env disable=SC1091
source .wayfinder/ci.env

version="${WF_CLI_VERSION:-}"
if [[ -n "${version}" ]]; then
  base="https://storage.googleapis.com/wayfinder-releases/${version}"
else
  base="https://storage.googleapis.com/wayfinder-dev-releases/latest"
fi

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m | sed 's/x86_64/amd64/')"

curl -fsSL "${base}/wf-cli-${os}-${arch}.tar.gz" -o /tmp/wf.tgz
tar -xzf /tmp/wf.tgz -C /tmp
sudo install -m 0755 "/tmp/wf-cli-${os}-${arch}" /usr/local/bin/wf
rm -f /tmp/wf.tgz

wf version
