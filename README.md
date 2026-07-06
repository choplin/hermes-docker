# Hermes Docker Template

A self-contained Docker Compose template for running [Hermes Agent](https://github.com/NousResearch/hermes-agent) with Docker, using the OpenCode Go API as the LLM backend.

## Files

- `Dockerfile`: Builds a container with Node 24 + Python + uv + Hermes Agent
- `docker-compose.yml`: Two services — `hermes` (gateway) and `dashboard` (web UI)
- `.env`: Configuration file for API keys and bootstrap settings
- `.env.example`: Template with all configurable variables
- `scripts/entrypoint.sh`: Non-interactive bootstrap, directory setup, and privilege drop
- `workspace/`: Mounted as `/workspace` inside the container — place project files here

## Quick Start

```bash
# 1. Set your OpenCode Go API key
cp .env.example .env
# Edit .env and set OPENCODE_GO_API_KEY

# 2. Build and start
docker compose up -d
```

## First-Time Setup (Post-Start)

### 1. Dashboard Authentication

The dashboard requires authentication when bound to `0.0.0.0`.

**OAuth (recommended):**

```bash
docker exec -it hermes bash -lc "hermes dashboard register --redirect-uri http://<your-host>:9119/auth/callback"
```

Complete the OAuth login in your browser, then restart the dashboard:

```bash
docker compose restart dashboard
```

Access the dashboard at `http://<your-host>:9119`.

**Password auth (alternative):**

```bash
docker exec -it hermes bash -lc "\
  HASH=\$(python -c 'from plugins.dashboard_auth.basic import hash_password; print(hash_password(\"your-password\"))'); \
  cat >> ~/.hermes/config.yaml << EOF

dashboard:
  basic_auth:
    username: admin
    password_hash: \"\$HASH\"
EOF
"
docker compose restart dashboard
```

### 2. Verify

Access the dashboard at `http://<your-host>:9119`. The "Gateway Status" should show as Running.

## Default Flow

1. On first start, `entrypoint.sh` runs as root:
   - Creates directories, fixes volume permissions
   - Generates an API key for the Gateway's API server
   - Configures `dashboard.gateway_url` so the dashboard can find the gateway
   - Symlinks `~/.hermes` → `/opt/data` (the persistent volume)
2. Runs non-interactive bootstrap (if no config exists):
   - Sets `provider` to `opencode-go`
   - Sets the main model to `kimi-k2.6`
   - Writes the API key from `OPENCODE_GO_API_KEY` to `.env`
3. Drops privileges to the `hermes` user and starts:
   - Gateway: `hermes gateway run` (messaging platforms + API server on port 8642)
   - Dashboard: `hermes dashboard --host 0.0.0.0` (web UI on port 9119)
4. On subsequent starts, existing config is detected and bootstrap is skipped

## Switching Models at Runtime

Use the `/model` slash command in the dashboard or CLI:

```
/model deepseek-v4-flash     # lightweight tasks
/model kimi-k2.6             # heavier tasks
```

## Services

| Service | Port | Access | Auth |
|---------|------|--------|------|
| Gateway API | `8642` | `http://<host>:8642/v1/models` | Bearer token (`API_SERVER_KEY`) |
| Dashboard | `9119` | `http://<host>:9119` | OAuth or password |

## Workspace

The `workspace/` directory is mounted at `/workspace` inside the container. This is where Hermes reads and writes project files. Start empty and place existing projects here as needed.

The `data/` directory holds runtime data (config, logs, sessions) — it's not intended for direct file access.

## Advanced Configuration

```bash
# Full interactive setup (messaging platforms, tools, skills, etc.)
docker exec -it hermes bash -lc "hermes setup"

# Open a CLI session inside the container
docker exec -it hermes bash -lc "hermes"
```

## Notes

- `scripts/entrypoint.sh` runs as root, sets up directories/permissions, then drops to `hermes` user
- `API_SERVER_KEY` is auto-generated on first start and stored in `~/.hermes/.env`
- Provider/model config key names may need adjustment if Hermes changes its internal naming
