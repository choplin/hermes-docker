#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/hermes}"
export HERMES_HOME="${HERMES_HOME:-/opt/data}"
export HERMES_DIR="${HERMES_DIR:-$HOME/.hermes}"
CONFIG_FILE="${HERMES_DIR}/config.yaml"
ENV_FILE="${HERMES_DIR}/.env"
BOOTSTRAP_FLAG="${HERMES_DIR}/.bootstrap-complete"

# Ensure the persistent volume mount is writable by the hermes user.
# On Docker Desktop (Windows/macOS), bind mounts are owned by root and
# chown is a no-op, so chmod 777 is the reliable workaround.
if [ "$(id -u)" -eq 0 ]; then
  mkdir -p "$HERMES_HOME"/logs "$HERMES_HOME"/sessions
  chown -R hermes:hermes "$HERMES_HOME" "$HOME" 2>/dev/null || :
  chmod -R 777 "$HERMES_HOME" 2>/dev/null || :
fi

mkdir -p "$HERMES_HOME" "$HERMES_DIR"

link_persistent_dir() {
  if [ ! -L "$HOME/.hermes" ]; then
    rm -rf "$HOME/.hermes"
    ln -s "$HERMES_HOME" "$HOME/.hermes"
  fi
}

has_nonempty_config() {
  [ -s "$CONFIG_FILE" ]
}

write_env_var() {
  local key="$1"
  local value="$2"
  touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE"; then
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
  hermes config set provider openrouter || :
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-openrouter/openai/gpt-4.1-mini}" || :
}

bootstrap_openai() {
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "[entrypoint] OPENAI_API_KEY is not set; skipping bootstrap" >&2
    return 0
  fi
  write_env_var OPENAI_API_KEY "$OPENAI_API_KEY"
  hermes config set provider openai || :
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-gpt-4.1-mini}" || :
}

bootstrap_opencode_go() {
  if [ -z "${OPENCODE_GO_API_KEY:-}" ]; then
    echo "[entrypoint] OPENCODE_GO_API_KEY is not set; skipping bootstrap" >&2
    return 0
  fi
  write_env_var OPENCODE_GO_API_KEY "$OPENCODE_GO_API_KEY"
  hermes config set provider opencode-go || :
  hermes config set model "${HERMES_BOOTSTRAP_MODEL:-kimi-k2.6}" || :
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

  hermes doctor || :
  touch "$BOOTSTRAP_FLAG"
}

link_persistent_dir
bootstrap_if_needed

# Ensure API_SERVER_KEY is set (used by Dashboard to communicate with Gateway)
if ! grep -q '^API_SERVER_KEY=' "$ENV_FILE" 2>/dev/null; then
  printf 'API_SERVER_KEY=%s\n' "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" >> "$ENV_FILE"
fi

# Tell Dashboard where to find the Gateway API
if ! grep -q '^dashboard.gateway_url=' "$CONFIG_FILE" 2>/dev/null; then
  echo "" >> "$CONFIG_FILE"
  echo "dashboard:" >> "$CONFIG_FILE"
  echo "  gateway_url: http://hermes:8642" >> "$CONFIG_FILE"
fi

# Drop root privileges to the hermes user
if [ "$(id -u)" -eq 0 ]; then
  exec su hermes -s /bin/bash -c "$(printf '%q ' "$@")"
else
  exec "$@"
fi
