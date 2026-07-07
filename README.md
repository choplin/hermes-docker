# Hermes Docker Template

A self-contained Docker Compose template for running [Hermes Agent](https://github.com/NousResearch/hermes-agent) with Docker, using OpenCode Go as the LLM backend.

## Files

- `Dockerfile`: Builds a container with Node 24 + Python + uv + Hermes Agent
- `docker-compose.yml`: Two services — `hermes` (gateway) and `dashboard` (web UI)
- `.env`: Configuration for API keys and bootstrap settings
- `.env.example`: Template with all configurable variables (copy to `.env` to start)
- `scripts/entrypoint.sh`: First-run bootstrap, directory setup, and privilege drop
- `data/`: Persistent runtime data (config, logs, sessions) — mounted at `~/.hermes`
- `workspace/`: Project files — mounted at `~/workspace`

## Usage

```bash
# 1. Configure your OpenCode Go API key
cp .env.example .env
# Edit .env and set OPENCODE_GO_API_KEY

# 2. Build and start both services
docker compose up -d

# 3. Access the dashboard
open http://localhost:9119
```

## First-Time Setup

After starting the containers, run the interactive setup wizard to configure messaging platforms, auxiliary models, and other options:

```bash
docker exec -it hermes bash -lc "hermes setup"
```

### Dashboard Authentication

The dashboard requires authentication when bound to `0.0.0.0`. Register with Nous Portal OAuth:

```bash
docker exec -it hermes bash -lc "hermes dashboard register --redirect-uri http://<your-host>:9119/auth/callback"
```

Complete the OAuth flow in your browser, then restart the dashboard:

```bash
docker compose restart dashboard
```

For password-based auth on a trusted LAN, see the [Hermes Web Dashboard docs](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard).

## Default Flow

1. On first start, `entrypoint.sh` runs as root:
   - Creates `~/.hermes/{logs,sessions}` inside the persistent volume
   - Generates `API_SERVER_KEY` and writes it to `~/.hermes/.env`
   - If no config exists, runs a non-interactive bootstrap (sets provider/model)
2. Runs `hermes gateway run` (messaging gateway + API server on port 8642)
3. On subsequent starts, existing config is detected and bootstrap is skipped
4. The dashboard runs separately with `hermes dashboard --host 0.0.0.0`

## Switching Models at Runtime

Use the `/model` slash command in the dashboard or CLI:

```
/model deepseek-v4-flash     # lightweight tasks
/model kimi-k2.6             # heavier tasks
```

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| Gateway | `hermes` | `8642` (API) | Messaging backend + OpenAI-compatible API |
| Dashboard | `hermes-dashboard` | `9119` | Web UI (OAuth or password auth) |

## Advanced

```bash
# Full interactive setup (messaging platforms, tools, skills, etc.)
docker exec -it hermes bash -lc "hermes setup"

# Open a CLI session
docker exec -it hermes bash -lc "hermes"

# View configuration
docker exec -it hermes bash -lc "hermes config"
```

## Notes

- `scripts/entrypoint.sh` runs as root, sets up directories and permissions, then drops to the `hermes` user
- The `data/` directory holds runtime state (config, sessions, logs) and is mounted at `~/.hermes`
- The `workspace/` directory holds project files and is mounted at `~/workspace`
- Provider/model config keys may change with Hermes Agent updates
