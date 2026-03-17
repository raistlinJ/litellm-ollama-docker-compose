# LiteLLM + Ollama HTTPS Proxy

This repository now uses explicit OS-specific compose files only. The generic default stack is gone.

Every stack in this repo assumes LiteLLM runs in Docker and talks to an Ollama instance outside the container. That Ollama instance can be:

- the local host machine
- another device on your LAN

All stacks use PostgreSQL-backed LiteLLM, so users, teams, keys, budgets, and UI-created models persist across restarts.

## Compose Layout

Root compose files are the nginx + self-signed certificate variants:

- `docker-compose-win.yml`
- `docker-compose-mac.yml`
- `docker-compose-linux.yml`

Caddy variants live under `caddy/`:

- `caddy/docker-compose-win.yml`
- `caddy/docker-compose-mac.yml`
- `caddy/docker-compose-linux.yml`

## Shared Environment

Create `.env` from `.env.example` and set these values before first start:

```dotenv
LITELLM_MASTER_KEY=sk-replace-with-a-random-secret
LITELLM_SALT_KEY=replace-with-a-long-random-secret-and-do-not-change-it-after-storing-models
UI_USERNAME=replace-with-a-ui-username
UI_PASSWORD=replace-with-a-random-ui-password
PROXY_BASE_URL=https://localhost
LITELLM_UI_SESSION_DURATION=24h
STORE_MODEL_IN_DB=True
POSTGRES_PASSWORD=replace-with-a-random-postgres-password
OLLAMA_API_BASE=http://host.docker.internal:11434
```

`LITELLM_SALT_KEY` protects credentials stored in the LiteLLM database. Set it before adding models or credentials through the UI, and do not rotate it casually afterward.

If Ollama runs on another device on your network, set `OLLAMA_API_BASE` to that device's LAN IP instead, for example `http://192.168.1.50:11434`.

## Windows

Use `docker-compose-win.yml` for the nginx + self-signed path.

1. Let Ollama listen for Docker Desktop:

```powershell
setx OLLAMA_HOST "0.0.0.0:11434"
```

Then fully restart the Ollama app.

2. Restrict direct inbound Ollama access to Docker Desktop or WSL:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\configure-ollama-firewall.ps1
```

3. Start the self-signed nginx stack:

```powershell
docker compose -f docker-compose-win.yml up -d
```

4. Trust the generated self-signed certificate:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trust-selfsigned-cert.ps1
```

5. Start the Caddy alternative instead, if you prefer Caddy's local CA flow:

```powershell
docker compose -f caddy/docker-compose-win.yml up -d
powershell -ExecutionPolicy Bypass -File .\scripts\trust-caddy-root.ps1
```

## macOS

Use `docker-compose-mac.yml` for the nginx + self-signed path.

1. Let host Ollama listen for Docker Desktop:

```bash
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
osascript -e 'quit app "Ollama"'
open -a Ollama
```

2. Restrict direct inbound Ollama access to Docker Desktop:

```bash
sudo sh ./scripts/configure-ollama-pf.sh
```

3. Start the self-signed nginx stack:

```bash
docker compose -f docker-compose-mac.yml up -d
```

4. Start the Caddy alternative instead:

```bash
docker compose -f caddy/docker-compose-mac.yml up -d
```

For macOS Caddy trust, import the local Caddy root CA into Keychain after the stack starts. On Windows there is a helper script; on macOS you can export the Caddy root from the container and trust it manually.

## Linux

Use `docker-compose-linux.yml` for the nginx + self-signed path.

The Linux compose files add `host.docker.internal:host-gateway` for LiteLLM, so host Ollama can be reached with the same default `OLLAMA_API_BASE` used on macOS and Windows.

1. Let host Ollama listen on all interfaces:

```bash
export OLLAMA_HOST="0.0.0.0:11434"
ollama serve
```

If Ollama is managed by systemd instead of a shell session, set the environment there and restart the service.

2. Start the self-signed nginx stack:

```bash
docker compose -f docker-compose-linux.yml up -d
```

3. Start the Caddy alternative instead:

```bash
docker compose -f caddy/docker-compose-linux.yml up -d
```

4. If Linux host firewalling is enabled, allow only the Docker host or the specific trusted subnet to reach Ollama on `11434`.

## Proxy Differences

nginx self-signed stacks:

- terminate HTTPS with `certs/server.crt` and `certs/server.key`
- auto-generate the cert pair on first start if missing
- use `scripts/trust-selfsigned-cert.ps1` on Windows to trust the cert

Caddy stacks:

- terminate HTTPS with `tls internal`
- generate and manage a local Caddy root CA automatically
- use `scripts/trust-caddy-root.ps1` on Windows to trust the Caddy CA

## Admin UI And Keys

After start, the main endpoints are:

- `https://localhost/ui`
- `https://localhost/v1/...`
- `https://localhost/key/...`
- `https://localhost/user/...`
- `https://localhost/team/...`

Use `LITELLM_MASTER_KEY` as the admin bearer token for management API calls. Use `UI_USERNAME` and `UI_PASSWORD` for the browser UI.

Example:

```bash
curl -sk https://localhost/key/generate \
  -H 'Authorization: Bearer sk-your-master-key' \
  -H 'Content-Type: application/json' \
  -d '{"models":["ollama/llama3.2"],"duration":"30d"}'
```

## Ollama Reachability

LiteLLM does not auto-import every Ollama tag it can reach. It only exposes the models you add in the LiteLLM UI or define in `litellm/config.yaml`.

The default config maps one model:

- `ollama/llama3.2`

If your actual Ollama host has different tags, add them in the LiteLLM UI under `Models + Endpoints` or extend `litellm/config.yaml`.

To verify reachability from inside the LiteLLM container, test the actual HTTP endpoint, not `ping`:

```bash
docker exec -it <litellm-container-name> sh
python - <<'PY'
import urllib.request
print(urllib.request.urlopen("http://host.docker.internal:11434/api/tags", timeout=5).read().decode())
PY
```

If Ollama lives on another machine, replace `host.docker.internal` with that machine's LAN IP.

## Common Commands

Windows self-signed:

```powershell
docker compose -f docker-compose-win.yml up -d
docker compose -f docker-compose-win.yml down
docker compose -f docker-compose-win.yml logs -f
```

macOS self-signed:

```bash
docker compose -f docker-compose-mac.yml up -d
docker compose -f docker-compose-mac.yml down
docker compose -f docker-compose-mac.yml logs -f
```

Linux self-signed:

```bash
docker compose -f docker-compose-linux.yml up -d
docker compose -f docker-compose-linux.yml down
docker compose -f docker-compose-linux.yml logs -f
```

Any Caddy variant:

```bash
docker compose -f caddy/docker-compose-<os>.yml up -d
docker compose -f caddy/docker-compose-<os>.yml down
docker compose -f caddy/docker-compose-<os>.yml logs -f
```

## Public Exposure

These stacks are intended for local or private-network use first.

If you want public internet exposure:

1. Do not expose Ollama directly.
2. Keep LiteLLM behind the HTTPS proxy only.
3. Replace the default local certificate strategy with a certificate issued for your real hostname.
4. Keep using a strong `LITELLM_MASTER_KEY` and a fixed `LITELLM_SALT_KEY`.
