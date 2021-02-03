#!/usr/bin/env bash

set -eu
set -o pipefail

readonly PROGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SAMPLESDIR="$(cd "${PROGDIR}/.." && pwd)"

# shellcheck source=SCRIPTDIR/.util/tools.sh
source "${PROGDIR}/.util/tools.sh"

# shellcheck source=SCRIPTDIR/.util/print.sh
source "${PROGDIR}/.util/print.sh"

function main() {
  local builderArray
  builderArray=()

  while [[ "${#}" != 0 ]]; do
    case "${1}" in
      --help|-h)
        shift 1
        usage
        exit 0
        ;;

      --builder|-b)
        builderArray+=("${2}")
        shift 2
        ;;

      "")
        # skip if the argument is empty
        shift 1
        ;;

      *)
        util::print::error "unknown argument \"${1}\""
    esac
  done

  if [[ ! -d "${SAMPLESDIR}/tests" ]]; then
      util::print::warn "** WARNING  No Smoke tests **"
  fi
  # TODO: fix unary operator
  if [ ! "${builderArray[@]}" ]; then
    builderArray+=("paketobuildpacks/builder:full")
  fi

  tools::install
  for name in "${builderArray[@]}"; do
    builder::pull "${name}"
    image::pull::lifecycle "${name}"
    image::pull::run_image "${name}"
  done

  tests::run "${builderArray[@]}"
}

function usage() {
  cat <<-USAGE
smoke.sh [OPTIONS]

Runs the smoke test suite.

OPTIONS
  --help        -h         prints the command usage
  --builder <name> -b <name>  sets the name of the builder that is built for testing
USAGE
}

function tools::install() {
  util::tools::pack::install \
    --directory "${SAMPLESDIR}/.bin"
}

function builder::pull() {
  local name
  name="${1}"

  util::print::title "Pulling latest builder..."
  docker pull "${name}"
}

function image::pull::lifecycle() {
  local name lifecycle_image
  name="${1}"

  lifecycle_image="index.docker.io/buildpacksio/lifecycle:$(
    pack inspect-builder "${name}" --output json \
      | jq -r '.local_info.lifecycle.version'
  )"

  util::print::title "Pulling lifecycle image..."
  docker pull "${lifecycle_image}"
}

function image::pull::run_image() {
  local name run_image
  name="${1}"

  run_image="$(pack inspect-builder "${name}" --output json \
      | jq -r '.local_info.run_images | .[0].name'
  )"

  util::print::title "Pulling run image..."
  docker pull "${run_image}"
}
function tests::run() {
  local builderArray
  builderArray=()
  while [[ "${#}" != 0 ]]; do
    case "${1}" in
      "")
        # skip if the argument is empty
        shift 1
        ;;

      *)
        builderArray+=("${1}")
        shift 1
        ;;

    esac
  done

  util::print::title "Run Samples Tests"

  testout=$(mktemp)
  pushd "${SAMPLESDIR}"/tests > /dev/null
    if GOMAXPROCS="${GOMAXPROCS:-4}" go test -count=1 -timeout 0 ./... -v -run Samples  --name "${builderArray[@]}" | tee "${testout}"; then
      util::tools::tests::checkfocus "${testout}"
      util::print::success "** GO Test Succeeded **"
    else
      util::print::error "** GO Test Failed **"
    fi
  popd > /dev/null
}

main "${@:-}"
