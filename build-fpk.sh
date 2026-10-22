#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${ROOT}/magpie"
PACKAGE="${ROOT}/fnos"
OUT="${ROOT}/dist"
STAGE_ROOT="${ROOT}/build/fpk-stage"
BIN_DIR="${ROOT}/build"
VERSION="${VERSION:-0.1.1320}"
UPSTREAM_TAG="${UPSTREAM_TAG:-v${VERSION}}"
DOCKER_IMAGE="${DOCKER_IMAGE:-debian:12-slim}"
FNPACK_LINUX="${ROOT}/tools/fnpack-linux-amd64"

command -v go >/dev/null 2>&1 || { echo "需要 Go 1.26+。" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "需要 Git。" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "需要 Docker（用 Linux fnpack 打包以保留可执行权限）。" >&2; exit 1; }

if [ ! -f "${SOURCE}/go.mod" ]; then
  if [ -d "${SOURCE}" ]; then
    echo "清理不完整的 magpie 源码目录：${SOURCE}" >&2
    rm -rf "${SOURCE}"
  fi
  echo "==> 获取上游 magpie ${UPSTREAM_TAG}"
  git clone --depth 1 --branch "${UPSTREAM_TAG}" https://github.com/yetone/magpie.git "${SOURCE}"
fi

PATCH_FILE="${ROOT}/patches/fnos-web-key.patch"
if [ -f "${PATCH_FILE}" ] && ! grep -q 'const webKeyMin = 6' "${SOURCE}/internal/gui/web.go"; then
  echo "==> 应用 fnOS 访问密钥补丁（最少 6 位，字母+数字）"
  git -C "${SOURCE}" apply "${PATCH_FILE}"
fi

PATCH_FILE="${ROOT}/patches/fnos-update.patch"
if [ -f "${PATCH_FILE}" ] && ! grep -q 'MAGPIE_FNOS_PACKAGE' "${SOURCE}/internal/gui/update.go"; then
  echo "==> 应用 fnOS 更新检查补丁（提示 FPK 下载页）"
  git -C "${SOURCE}" apply "${PATCH_FILE}"
fi

if [ ! -f "${FNPACK_LINUX}" ]; then
  mkdir -p "${ROOT}/tools"
  echo "下载 fnpack 1.2.3 (linux-amd64)"
  curl -fsSL "https://static2.fnnas.com/fnpack/fnpack-1.2.3-linux-amd64" -o "${FNPACK_LINUX}"
  chmod +x "${FNPACK_LINUX}"
fi

mkdir -p "${OUT}" "${STAGE_ROOT}" "${BIN_DIR}"

build_one() {
  arch=$1
  platform=$2

  echo "==> 编译 linux/${arch}（magpie ${VERSION}）"
  (cd "${SOURCE}" && CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
    go build -tags nogui -trimpath \
    -ldflags="-s -w -X main.version=${VERSION}" \
    -o "${BIN_DIR}/magpie-linux-${arch}" .)

  stage="${STAGE_ROOT}/${platform}"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  cp -a "${PACKAGE}/." "${stage}/"
  rm -f "${stage}/manifest.template"
  rm -f "${stage}/app/bin/.gitkeep" "${stage}/app/ui/images/.gitkeep"

  mkdir -p "${stage}/app/bin" "${stage}/app/ui/images"
  cp "${BIN_DIR}/magpie-linux-${arch}" "${stage}/app/bin/magpie"
  cp "${SOURCE}/internal/gui/icon.png" "${stage}/ICON.PNG"
  cp "${SOURCE}/internal/gui/icon-256.png" "${stage}/ICON_256.PNG"
  cp "${SOURCE}/internal/gui/icon.png" "${stage}/app/ui/images/icon_64.png"
  cp "${SOURCE}/internal/gui/icon-256.png" "${stage}/app/ui/images/icon_256.png"
  cp "${SOURCE}/LICENSE" "${stage}/app/LICENSE"

  sed -e "s/@VERSION@/${VERSION}/g" -e "s/@PLATFORM@/${platform}/g" \
    "${PACKAGE}/manifest.template" > "${stage}/manifest"

  chmod 755 "${stage}/cmd" "${stage}"/cmd/*
  chmod 755 "${stage}/app/bin/magpie"
  chmod 644 "${stage}/manifest" "${stage}/Magpie.sc" \
    "${stage}/config/privilege" "${stage}/config/resource" \
    "${stage}/wizard/install" "${stage}/wizard/uninstall" \
    "${stage}/app/ui/config" "${stage}/app/ui/images/"*.png \
    "${stage}/ICON.PNG" "${stage}/ICON_256.PNG" "${stage}/app/LICENSE"

  echo "==> 用 fnpack 1.2.3 打包 ${platform}"
  MSYS_NO_PATHCONV=1 docker run --rm \
    -e PLATFORM="${platform}" -e VERSION="${VERSION}" \
    -v "${ROOT}:/work" -v "${ROOT}/tools:/tools:ro" \
    "${DOCKER_IMAGE}" sh /work/scripts/docker-fnpack.sh

  test -f "${OUT}/magpie_${VERSION}_${platform}.fpk"
  echo "==> ${OUT}/magpie_${VERSION}_${platform}.fpk"
}

build_one amd64 x86
build_one arm64 arm

cd "${OUT}"
sha256sum "magpie_${VERSION}_x86.fpk" "magpie_${VERSION}_arm.fpk" > SHA256SUMS.txt
ls -lh "magpie_${VERSION}_x86.fpk" "magpie_${VERSION}_arm.fpk" SHA256SUMS.txt
