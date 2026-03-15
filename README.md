# LiteLLM + Ollama HTTPS Proxy

This project runs a local HTTPS endpoint on Windows using Docker Desktop:

- Caddy terminates HTTPS on `https://localhost`
- Caddy proxies requests to LiteLLM
- LiteLLM routes model calls to Ollama

The resulting endpoint is an OpenAI-compatible HTTPS API backed by Ollama.

## Architecture

`client -> https://localhost -> Caddy -> LiteLLM -> Ollama`

## Prerequisites

- Windows 11 or Windows 10 with Docker Desktop installed
- Docker Desktop using the WSL 2 backend
- PowerShell

Optional:

- NVIDIA GPU support in Docker Desktop if you want GPU-backed Ollama inference

## Quick Start

1. Create your environment file:

```powershell
Copy-Item .env.example .env
```

2. Edit `.env` and set a strong random value for `LITELLM_MASTER_KEY`.

3. Start the stack:

```powershell
docker compose up -d
```

4. Pull the default Ollama model:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pull-model.ps1
```

5. Trust the local Caddy certificate authority on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trust-caddy-root.ps1
```

6. Test the HTTPS endpoint:

```powershell
curl.exe https://localhost/v1/models `
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY"
```

7. Send a chat completion request:

```powershell
curl.exe https://localhost/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" `
  -d "{\"model\":\"ollama/llama3.2\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello from LiteLLM over HTTPS.\"}]}"
```

## Exposed Endpoint

- Base URL: `https://localhost`
- LiteLLM/OpenAI-compatible API path: `https://localhost/v1/...`

Ollama is not published directly to the host. It is only reachable through LiteLLM inside Docker.

## Default Model Mapping

LiteLLM exposes this default model:

- `ollama/llama3.2`

If you pull additional Ollama models, add them to `litellm/config.yaml` so LiteLLM can route them by name.

## Common Commands

Start:

```powershell
docker compose up -d
```

Stop:

```powershell
docker compose down
```

View logs:

```powershell
docker compose logs -f
```

Pull a different model:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pull-model.ps1 -Model mistral
```

## Self-Signed TLS Option

You do not need nginx for this. Caddy can terminate HTTPS directly, and the self-signed variant uses a one-shot helper container to create `certs/server.crt` and `certs/server.key` if they do not already exist.

Use the separate self-signed compose file when you want to avoid ACME or public certificate issuance:

```powershell
docker compose -f docker-compose-selfsigned.yml up -d
```

What happens on first start:

- `certgen` creates a self-signed certificate if `certs/server.crt` and `certs/server.key` are missing
- Caddy starts with that certificate and exposes HTTPS on port `443`
- LiteLLM remains behind Caddy and still enforces `LITELLM_MASTER_KEY`

The certificate settings come from `.env`:

- `SELF_SIGNED_CERT_CN=host.example.com`
- `SELF_SIGNED_CERT_SAN=DNS:host.example.com,DNS:localhost,IP:127.0.0.1`
- `SELF_SIGNED_CERT_DAYS=825`

`host.example.com` is only a placeholder sample hostname. Replace it with your real public hostname when needed.

After the first startup, trust the generated certificate on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trust-selfsigned-cert.ps1
```

If you delete files under `certs/`, the next `docker compose -f docker-compose-selfsigned.yml up -d` run will generate a new certificate pair.

## Internet Exposure

This setup uses Caddy's internal CA and is appropriate for local or private-network use.

If you want to expose this to the public internet, replace the `localhost` hostnames in `Caddyfile` with a real DNS name and use a public certificate instead of `tls internal`.

## Public Exposure Notes

For your setup, clients would connect to:

- `https://host.example.com:YOUR_PUBLIC_PORT/v1/...`

Using a non-standard public port is acceptable for connectivity, but it does not materially improve security. Treat it only as noise reduction.

### Important TLS Constraint

If you want a browser-trusted public certificate from Let's Encrypt, ACME validation must be able to reach your hostname on standard validation ports.

- `HTTP-01` requires public port `80`
- `TLS-ALPN-01` requires public port `443`

If your router only exposes a non-standard external port that forwards to container port `443`, automatic certificate issuance will usually fail.

That means you need one of these approaches:

1. Forward public `80` and `443` to the Windows host so Caddy can obtain and renew a normal public certificate.
2. Use DNS challenge with a Caddy build that includes a DNS provider plugin supported by your DNS provider.
3. Keep `tls internal` and manually trust the Caddy root certificate on every client device that will access the service.

If this is just for your own devices, option `3` can work. If this is meant to behave like a normal public HTTPS service, option `1` is the simplest reliable choice.

### LiteLLM API Key Security

LiteLLM does provide access control through `LITELLM_MASTER_KEY`, and it is the right authentication layer for the API itself. But it is not a full edge-security solution.

What it does give you:

- Bearer-token authentication for API access
- A clean OpenAI-compatible auth model for clients

What it does not give you by itself:

- IP allowlisting
- WAF or bot filtering
- DDoS protection
- Automatic brute-force throttling at the network edge
- TLS certificate issuance strategy

For an internet-facing home deployment, the practical model is:

- Caddy handles HTTPS at the edge
- LiteLLM enforces API-key authentication
- Windows Firewall restricts exposure as much as possible
- Router forwards only the single HTTPS port you intentionally expose

### Recommended Settings

If you proceed with direct port forwarding, I recommend:

1. Use a long random `LITELLM_MASTER_KEY`.
2. Expose only the HTTPS listener. Do not publish Ollama directly.
3. Keep the proxy limited to `/v1/*` routes only.
4. Watch `docker compose logs -f caddy litellm` for abuse or repeated unauthorized requests.
5. If you can, allow only known source IPs in Windows Firewall.

### Recommended Public Caddyfile Shape

If you later switch to a public certificate, the host block should look conceptually like this:

```caddy
https://host.example.com {
  encode zstd gzip

  header {
    X-Content-Type-Options nosniff
    X-Frame-Options DENY
    Referrer-Policy no-referrer
  }

  @openai_api path /v1/*
  handle @openai_api {
    reverse_proxy litellm:4000
  }

  handle {
    respond "Not found" 404
  }
}
```
