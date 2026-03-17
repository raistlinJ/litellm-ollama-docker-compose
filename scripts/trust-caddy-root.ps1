$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$certDir = Join-Path $projectRoot "certs"
$certPath = Join-Path $certDir "caddy-local-root.crt"

New-Item -ItemType Directory -Force -Path $certDir | Out-Null

$runningCaddy = docker ps --format "{{.ID}} {{.Names}}" |
	Where-Object { $_ -match "litellm-ollama-proxy-.*-caddy-1$" } |
	Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($runningCaddy)) {
	throw "No running Caddy container was found. Start one of the caddy/docker-compose-*.yml stacks first."
}

$containerId = ($runningCaddy -split " ")[0]
docker cp "${containerId}:/data/caddy/pki/authorities/local/root.crt" $certPath | Out-Null

if (-not (Test-Path $certPath)) {
	throw "Failed to export the Caddy local root certificate to $certPath."
}

Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null

Write-Host "Imported Caddy local CA into CurrentUser\\Root: $certPath"
