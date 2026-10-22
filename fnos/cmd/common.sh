#!/bin/sh
# Shared paths and helpers for the Magpie fnOS package.
set -eu

CMD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "${CMD_DIR}/.." && pwd)

if [ -n "${TRIM_APPDEST:-}" ]; then
  APP_DEST=${TRIM_APPDEST}
elif [ -d "${PACKAGE_ROOT}/target" ]; then
  APP_DEST="${PACKAGE_ROOT}/target"
else
  APP_DEST="${PACKAGE_ROOT}/app"
fi

if [ -n "${TRIM_PKGVAR:-}" ]; then
  PKG_VAR=${TRIM_PKGVAR}
elif [ -d "${PACKAGE_ROOT}/var" ]; then
  PKG_VAR="${PACKAGE_ROOT}/var"
else
  PKG_VAR="${PACKAGE_ROOT}/app/data"
fi

MAGPIE_BIN="${APP_DEST}/bin/magpie"
HOME_DIR="${PKG_VAR}/home"
CONFIG_HOME="${PKG_VAR}/config"
CACHE_HOME="${PKG_VAR}/cache"
DATA_HOME="${PKG_VAR}/data"
STATE_HOME="${PKG_VAR}/state"
LOG_DIR="${PKG_VAR}/logs"
RUN_DIR="${PKG_VAR}/run"
KEY_FILE="${PKG_VAR}/web.key"
PUBLIC_URL_FILE="${PKG_VAR}/public-url"
UPDATE_FEED_FILE="${PKG_VAR}/update-feed-url"
DEFAULT_UPDATE_FEED="https://github.com/SMTM-PH/magpie-fnos/releases/latest/download/update-feed.json"
APP_CA="${APP_DEST}/certs/cacert.pem"
USER_CA="${PKG_VAR}/ca-cert.pem"
CA_BUNDLE="${RUN_DIR}/ca-bundle.pem"
PID_FILE="${RUN_DIR}/magpie.pid"
LOG_FILE="${LOG_DIR}/magpie.log"
LIFECYCLE_LOG="${LOG_DIR}/lifecycle.log"

GATEWAY_PORT=3425
WEB_PORT=3430

prepare_dirs() {
  umask 077
  mkdir -p "${HOME_DIR}" "${CONFIG_HOME}" "${CACHE_HOME}" "${DATA_HOME}" \
           "${STATE_HOME}" "${LOG_DIR}" "${RUN_DIR}"
}

prepare_ca_bundle() {
  cert_tmp="${CA_BUNDLE}.tmp"
  : > "${cert_tmp}"
  if [ -f "${APP_CA}" ]; then
    cat "${APP_CA}" >> "${cert_tmp}"
  fi
  if [ -f "${USER_CA}" ]; then
    cat "${USER_CA}" >> "${cert_tmp}"
  fi
  if [ -s "${cert_tmp}" ]; then
    chmod 644 "${cert_tmp}"
    mv -f "${cert_tmp}" "${CA_BUNDLE}"
  else
    rm -f "${cert_tmp}" "${CA_BUNDLE}"
  fi
}

log_msg() {
  mkdir -p "${LOG_DIR}"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${LOG_FILE}"
}

fail() {
  message=$1
  printf '%s\n' "${message}" >&2
  if [ -n "${TRIM_TEMP_LOGFILE:-}" ]; then
    printf '%s\n' "${message}" > "${TRIM_TEMP_LOGFILE}"
  fi
  exit 1
}

rotate_log() {
  [ -f "${LOG_FILE}" ] || return 0
  size=$(wc -c < "${LOG_FILE}" 2>/dev/null | tr -d '[:space:]') || return 0
  case "${size}" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "${size}" -ge 5242880 ]; then
    mv -f "${LOG_FILE}" "${LOG_FILE}.1"
  fi
}

valid_key() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9]{6,128}$'
}

# valid_stored_key also accepts - . _ ~ so a key set by an older package
# keeps working after an upgrade; new keys are restricted by valid_key.
valid_stored_key() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._~-]{6,128}$'
}

new_key() {
  od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
}

write_key() {
  umask 077
  printf '%s\n' "$1" > "${KEY_FILE}.tmp"
  mv -f "${KEY_FILE}.tmp" "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
}

web_key() {
  if [ -f "${KEY_FILE}" ]; then
    existing=$(head -n 1 "${KEY_FILE}" | tr -d '\r\n')
    if valid_stored_key "${existing}"; then
      printf '%s' "${existing}"
      return 0
    fi
    log_msg "existing web access key is invalid; generating a new one"
  fi
  generated=$(new_key)
  write_key "${generated}"
  log_msg "generated a new web access key (see ${KEY_FILE})"
  printf '%s' "${generated}"
}

canonical_bin() {
  bin_dir=$(CDPATH= cd -- "$(dirname -- "${MAGPIE_BIN}")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s' "${bin_dir}" "$(basename -- "${MAGPIE_BIN}")"
}

process_alive() {
  pid=$1
  case "${pid}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "${pid}" 2>/dev/null || return 1
  state=$(awk '/^State:/{print $2; exit}' "/proc/${pid}/status" 2>/dev/null) || state=""
  [ "${state}" != "Z" ]
}

is_our_process() {
  pid=$1
  process_alive "${pid}" || return 1
  expected=$(canonical_bin) || return 1
  executable=$(readlink "/proc/${pid}/exe" 2>/dev/null) || return 1
  executable=${executable% (deleted)}
  [ "${executable}" = "${expected}" ] || return 1
  process_uid=$(awk '/^Uid:/{print $2; exit}' "/proc/${pid}/status" 2>/dev/null) || process_uid=""
  [ -z "${process_uid}" ] || [ "${process_uid}" = "$(id -u)" ] || return 1
  return 0
}

read_pid() {
  if [ -f "${PID_FILE}" ]; then
    head -n 1 "${PID_FILE}" | tr -d '[:space:]'
  fi
}

healthcheck() {
  env HOME="${HOME_DIR}" \
      XDG_CONFIG_HOME="${CONFIG_HOME}" \
      XDG_CACHE_HOME="${CACHE_HOME}" \
      XDG_DATA_HOME="${DATA_HOME}" \
      XDG_STATE_HOME="${STATE_HOME}" \
      MAGPIE_ADDR="127.0.0.1:${GATEWAY_PORT}" \
      "${MAGPIE_BIN}" healthcheck >/dev/null 2>&1
}

port_busy() {
  port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
  else
    return 1
  fi
}

detect_public_url() {
  ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}') || ip=""
  fi
  if [ -z "${ip}" ] && command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1) || ip=""
  fi
  case "${ip}" in
    ""|127.*|0.0.0.0) ;;
    *) printf 'http://%s:%s' "${ip}" "${GATEWAY_PORT}" ;;
  esac
}

export_runtime_env() {
  key=$1
  export HOME="${HOME_DIR}"
  export XDG_CONFIG_HOME="${CONFIG_HOME}"
  export XDG_CACHE_HOME="${CACHE_HOME}"
  export XDG_DATA_HOME="${DATA_HOME}"
  export XDG_STATE_HOME="${STATE_HOME}"
  export MAGPIE_ADDR="0.0.0.0:${GATEWAY_PORT}"
  export MAGPIE_WEB_KEY="${key}"
  # The FPK owns the binary. The update check reads our release feed and
  # opens the FPK download page instead of replacing the binary.
  export MAGPIE_FNOS_PACKAGE=1
  update_feed="${DEFAULT_UPDATE_FEED}"
  if [ -f "${UPDATE_FEED_FILE}" ]; then
    custom_feed=$(head -n 1 "${UPDATE_FEED_FILE}" | tr -d '\r\n') || custom_feed=""
    case "${custom_feed}" in
      http://*|https://*) update_feed="${custom_feed}" ;;
      "") ;;
      *) log_msg "ignoring invalid update feed: ${custom_feed}" ;;
    esac
  fi
  export MAGPIE_UPDATE_FEED="${update_feed}"

  # Use the bundled Mozilla roots (plus an optional user CA) so HTTPS works
  # even when the NAS image ships no ca-certificates, and so Bun, curl and
  # Python MCP servers trust the same roots as magpie itself.
  if [ -s "${CA_BUNDLE}" ]; then
    export SSL_CERT_FILE="${CA_BUNDLE}"
    export CURL_CA_BUNDLE="${CA_BUNDLE}"
    export NODE_EXTRA_CA_CERTS="${CA_BUNDLE}"
    export REQUESTS_CA_BUNDLE="${CA_BUNDLE}"
  fi

  public_url=""
  if [ -f "${PUBLIC_URL_FILE}" ]; then
    public_url=$(head -n 1 "${PUBLIC_URL_FILE}" | tr -d '\r\n') || public_url=""
  fi
  if [ -z "${public_url}" ]; then
    public_url=$(detect_public_url) || public_url=""
  fi
  if [ -n "${public_url}" ]; then
    export MAGPIE_PUBLIC_URL="${public_url}"
  fi
}

ensure_auto_update_off() {
  mkdir -p "${LOG_DIR}"
  env HOME="${HOME_DIR}" \
      XDG_CONFIG_HOME="${CONFIG_HOME}" \
      XDG_CACHE_HOME="${CACHE_HOME}" \
      XDG_DATA_HOME="${DATA_HOME}" \
      XDG_STATE_HOME="${STATE_HOME}" \
      "${MAGPIE_BIN}" update auto off notify >> "${LIFECYCLE_LOG}" 2>&1 \
    || log_msg "could not configure Magpie automatic updates"
}
