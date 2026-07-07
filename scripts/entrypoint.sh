#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/hermes}"
export HERMES_HOME="${HERMES_HOME:-/home/hermes/.hermes}"
CONFIG_FILE="${HERMES_HOME}/config.yaml"
ENV_FILE="${HERMES_HOME}/.env"
BOOTSTRAP_FLAG="${HERMES_HOME}/.bootstrap-complete"

# Ensure persistent directories exist with correct ownership.
# On Docker Desktop (Windows/macOS), chown on bind mounts is a no-op,
# so we fall back to world-writable permissions as a workaround.
if [ "$(id -u)" -eq 0 ]; then
  mkdir -p "$HERMES_HOME"/{logs,sessions}
  if ! chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null; then
    # chown failed (e.g. Docker Desktop bind mount) — try chmod instead
    chmod -R 777 "$HERMES_HOME" 2>/dev/null || \
      echo "[entrypoint] warning: could not set permissions on $HERMES_HOME" >&2
  fi
fi

mkdir -p "$HERMES_HOME"

has_nonempty_config() {
  [ -s "$CONFIG_FILE" ]
}

write_env_var() {
  local key="$1"
  local value="$2"
  touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

bootstrap_openrouter() {
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo "[entrypoint] OPENROUTER_API_KEY is not set; skipping bootstrap" >&2
    return 0
  fi
  write_env_var OPENROUTER_API_KEY "$OPENROUTER_API_KEY"
  hermes config set provider openrouter
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-openrouter/openai/gpt-4.1-mini}"
}

bootstrap_openai() {
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "[entrypoint] OPENAI_API_KEY is not set; skipping bootstrap" >&2
    return 0
  fi
  write_env_var OPENAI_API_KEY "$OPENAI_API_KEY"
  hermes config set provider openai
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-gpt-4.1-mini}"
}

bootstrap_opencode_go() {
  if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
    echo "[entrypoint] OPENCODE_GO_API_KEY is not set; skipping bootstrap" >&2
    return 0
  fi
  write_env_var OPENCODE_GO_API_KEY "$OPENCODE_GO_API_KEY"
  hermes config set provider opencode-go
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-kimi-k2.6}"
}

bootstrap_if_needed() {
  if [ "${HERMES_BOOTSTRAP_ON_START:-1}" != "1" ]; then
    echo "[entrypoint] bootstrap disabled"
    return 0
  fi

  if has_nonempty_config && [ -f "$BOOTSTRAP_FLAG" ]; then
    echo "[entrypoint] existing Hermes config detected; skipping bootstrap"
    return 0
  fi

  echo "[entrypoint] no complete config detected; running non-interactive bootstrap"
  case "${HERMES_BOOTSTRAP_PROVIDER:-opencode-go}" in
    openrouter)  bootstrap_openrouter ;;
    openai)      bootstrap_openai ;;
    opencode-go) bootstrap_opencode_go ;;
    *)
      echo "[entrypoint] unsupported HERMES_BOOTSTRAP_PROVIDER=${HERMES_BOOTSTRAP_PROVIDER}" >&2
      ;;
  esac

  if [ -f "$CONFIG_FILE" ]; then
    hermes doctor || echo "[entrypoint] hermes doctor reported issues (non-fatal)" >&2
  fi
  touch "$BOOTSTRAP_FLAG"
}

bootstrap_if_needed

# Ensure API_SERVER_KEY is set (used by external clients to call the API server).
if ! grep -q '^API_SERVER_KEY=' "$ENV_FILE" 2>/dev/null; then
  printf 'API_SERVER_KEY=%s\n' "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" >> "$ENV_FILE"
fi

# Drop root privileges to the hermes user
if [ "$(id -u)" -eq 0 ]; then
  exec su hermes -s /bin/bash -c "$(printf '%q ' "$@")"
else
  exec "$@"
fi
