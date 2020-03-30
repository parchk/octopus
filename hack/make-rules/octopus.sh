#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# The root of the octopus directory
ROOT_DIR="${CURR_DIR}"
source "${ROOT_DIR}/hack/lib/init.sh"
source "${CURR_DIR}/hack/lib/constant.sh"

function generate() {
  octopus::log::info "generating octopus..."

  octopus::log::info "generating objects"
  rm -f "${CURR_DIR}/api/*/zz_generated*"
  octopus::controller_gen::generate \
    object:headerFile="${ROOT_DIR}/hack/boilerplate.go.txt" \
    paths="${CURR_DIR}/api/..."

  octopus::log::info "generating protos"
  rm -f "${CURR_DIR}/pkg/adaptor/api/*/*.pb.go"
  for d in $(octopus::util::find_subdirs "${CURR_DIR}/pkg/adaptor/api"); do
    octopus::protoc::generate \
      "${CURR_DIR}/pkg/adaptor/api/${d}"
  done

  octopus::log::info "generating manifests"
  # generate crd
  octopus::controller_gen::generate \
    crd:crdVersions=v1 \
    paths="${CURR_DIR}/api/..." \
    output:crd:dir="${CURR_DIR}/deploy/manifests/crd/base"
  # generate webhook
  octopus::controller_gen::generate \
    webhook \
    paths="${CURR_DIR}/api/..." \
    output:webhook:dir="${CURR_DIR}/deploy/manifests/overlays/default"
  # generate rbac role
  octopus::controller_gen::generate \
    rbac:roleName=manager-role \
    paths="${CURR_DIR}/pkg/..." \
    output:rbac:dir="${CURR_DIR}/deploy/manifests/rbac"

  octopus::log::info "merging manifests"
  if ! octopus::kubectl::validate; then
    octopus::log::fatal "kubectl hasn't been installed"
  fi
  kubectl kustomize "${CURR_DIR}/deploy/manifests/overlays/default" \
    >"${CURR_DIR}/deploy/e2e/all_in_one.yaml"
  kubectl kustomize "${CURR_DIR}/deploy/manifests/overlays/without_webhook" \
    >"${CURR_DIR}/deploy/e2e/all_in_one_without_webhook.yaml"
  # replace the admissionregistration version
  sed "s#admissionregistration.k8s.io/v1beta1#admissionregistration.k8s.io/v1#g" "${CURR_DIR}/deploy/e2e/all_in_one.yaml" >/tmp/all_in_one.yaml
  mv /tmp/all_in_one.yaml "${CURR_DIR}/deploy/e2e/all_in_one.yaml"

  octopus::log::info "...done"
}

function mod() {
  [[ "${1:-}" != "only" ]] && generate
  pushd "${ROOT_DIR}" >/dev/null || exist 1
  octopus::log::info "downloading dependencies for octopus..."

  if [[ "$(go env GO111MODULE)" == "off" ]]; then
    octopus::log::warn "go mod has been disabled by GO111MODULE=off"
  else
    octopus::log::info "tidying"
    go mod tidy
    octopus::log::info "vending"
    go mod vendor
  fi

  octopus::log::info "...done"
  popd >/dev/null || return
}

function lint() {
  [[ "${1:-}" != "only" ]] && mod
  octopus::log::info "linting octopus..."

  local targets=(
    "${CURR_DIR}/api/..."
    "${CURR_DIR}/cmd/..."
    "${CURR_DIR}/pkg/..."
    "${CURR_DIR}/test/..."
    "${CURR_DIR}/template/..."
  )
  octopus::lint::generate "${targets[@]}"

  octopus::log::info "...done"
}

function build() {
  [[ "${1:-}" != "only" ]] && lint
  octopus::log::info "building octopus..."

  mkdir -p "${CURR_DIR}/bin"

  local version_flags="
    -X k8s.io/client-go/pkg/version.gitVersion=${OCTOPUS_GIT_VERSION}
    -X k8s.io/client-go/pkg/version.gitCommit=${OCTOPUS_GIT_COMMIT}
    -X k8s.io/client-go/pkg/version.gitTreeState=${OCTOPUS_GIT_TREE_STATE}
    -X k8s.io/client-go/pkg/version.buildDate=${OCTOPUS_BUILD_DATE}"
  local flags="
    -w -s"
  local ext_flags="
    -extldflags '-static'"

  local platforms
  if [[ "${CROSS:-false}" == "true" ]]; then
    octopus::log::info "crossed building"
    platforms=("${SUPPORTED_PLATFORMS[@]}")
  else
    local os="${OS:-$(go env GOOS)}"
    local arch="${ARCH:-$(go env GOARCH)}"
    platforms=("${os}/${arch}")
  fi

  for platform in "${platforms[@]}"; do
    octopus::log::info "building ${platform}"

    local os_arch
    IFS="/" read -r -a os_arch <<<"${platform}"

    local os=${os_arch[0]}
    local arch=${os_arch[1]}
    GOOS=${os} GOARCH=${arch} CGO_ENABLED=0 go build \
      -ldflags "${version_flags} ${flags} ${ext_flags}" \
      -o "${CURR_DIR}/bin/octopus_${os}_${arch}" \
      "${CURR_DIR}/cmd/octopus/main.go"
  done

  octopus::log::info "...done"
}

function package() {
  [[ "${1:-}" != "only" ]] && build
  octopus::log::info "packaging octopus..."

  local repo=${REPO:-rancher}
  local image_name=${IMAGE_NAME:-octopus}
  local tag=${TAG:-${OCTOPUS_GIT_VERSION}}

  local platforms
  if [[ "${CROSS:-false}" == "true" ]]; then
    octopus::log::info "crossed packaging"
    platforms=("${SUPPORTED_PLATFORMS[@]}")
  else
    local os="${OS:-$(go env GOOS)}"
    local arch="${ARCH:-$(go env GOARCH)}"
    platforms=("${os}/${arch}")
  fi

  pushd "${CURR_DIR}" >/dev/null 2>&1
  for platform in "${platforms[@]}"; do
    octopus::log::info "packaging ${platform}"
    if [[ "${platform}" =~ darwin/* ]]; then
      octopus::log::warn "package into Darwin OS image is unavailable, please use CROSS=true env to containerize multiple arch images or use OS=linux ARCH=amd64 env to containerize linux/amd64 image"
    fi
    octopus::docker::build \
      --platform "${platform}" \
      -t "${repo}/${image_name}:${tag}-${platform////-}" .
  done
  popd >/dev/null 2>&1

  octopus::log::info "...done"
}

function deploy() {
  [[ "${1:-}" != "only" ]] && package
  octopus::log::info "deploying octopus..."

  local repo=${REPO:-rancher}
  local image_name=${IMAGE_NAME:-octopus}
  local tag=${TAG:-${OCTOPUS_GIT_VERSION}}
  local images=()
  for platform in "${SUPPORTED_PLATFORMS[@]}"; do
    images+=("${repo}/${image_name}:${tag}-${platform////-}")
  done

  # docker login
  if [[ -n ${DOCKER_USERNAME} ]] && [[ -n ${DOCKER_PASSWORD} ]]; then
    docker login -u "${DOCKER_USERNAME}" -p "${DOCKER_PASSWORD}"
  fi

  # docker push
  for image in "${images[@]}"; do
    octopus::log::info "deploying image ${image}"
    docker push "${image}"
  done

  # docker manifest
  local targets=(
    "${repo}/${image_name}:${tag}"
    "${repo}/${image_name}:latest"
  )
  for target in "${targets[@]}"; do
    octopus::log::info "deploying manifest image ${target}"
    octopus::docker::manifest_create "${target}" "${images[@]}"
    octopus::docker::manifest_push "${target}"
  done

  octopus::log::info "...done"
}

function test() {
  [[ "${1:-}" != "only" ]] && build
  octopus::log::info "running unit tests for octopus..."

  local unit_test_targets=(
    "${CURR_DIR}/api/..."
    "${CURR_DIR}/cmd/..."
    "${CURR_DIR}/pkg/..."
  )

  if [[ "${CROSS:-false}" == "true" ]]; then
    octopus::log::warn "crossed test is not supported"
  fi

  local os="${OS:-$(go env GOOS)}"
  local arch="${ARCH:-$(go env GOARCH)}"
  if [[ "${arch}" == "arm" ]]; then
    # NB(thxCode): race detector doesn't support `arm` arch, ref to:
    # - https://golang.org/doc/articles/race_detector.html#Supported_Systems
    GOOS=${os} GOARCH=${arch} CGO_ENABLED=1 go test \
      -cover -coverprofile "${CURR_DIR}/dist/coverage_${os}_${arch}.out" \
      "${unit_test_targets[@]}"
  else
    GOOS=${os} GOARCH=${arch} CGO_ENABLED=1 go test \
      -race \
      -cover -coverprofile "${CURR_DIR}/dist/coverage_${os}_${arch}.out" \
      "${unit_test_targets[@]}"
  fi

  octopus::log::info "...done"
}

function verify() {
  [[ "${1:-}" != "only" ]] && test
  octopus::log::info "running integration tests for octopus..."

  CGO_ENABLED=1 go test \
    "${CURR_DIR}/test/integration/brain/..."
  #  CGO_ENABLED=1 go test \
  #    "${CURR_DIR}/test/integration/limb/..."

  octopus::log::info "...done"
}

function e2e() {
  [[ "${1:-}" != "only" ]] && verify
  octopus::log::info "running E2E tests for octopus..."

  octopus::log::info "...done"
}

function entry() {
  local stage
  stage="${1:-build}"
  shift

  case $stage in
  g | gen | generate) generate ;;
  m | mod) mod "$@" ;;
  l | lint) lint "$@" ;;
  b | build) build "$@" ;;
  p | pkg | package) package "$@" ;;
  d | dep | deploy) deploy "$@" ;;
  t | test) test "$@" ;;
  v | ver | verify) verify "$@" ;;
  e | e2e) e2e "$@" ;;
  *) octopus::log::fatal "unknown action, select from (generate,mod,lint,build,test,verify,package,deploy,e2e)" ;;
  esac
}

if [[ ${BY:-} == "dapper" ]]; then
  octopus::dapper::run -C "${CURR_DIR}" -f "Dockerfile.dapper" -m bind "$@"
else
  entry "$@"
fi