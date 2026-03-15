$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$certDir = Join-Path $projectRoot "certs"
$certPath = Join-Path $certDir "caddy-local-root.crt"

New-Item -ItemType Directory -Force -Path $certDir | Out-Null
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt $certPath
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null

Write-Host "Imported Caddy local CA into CurrentUser\\Root: $certPath"
