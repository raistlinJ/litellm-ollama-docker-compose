$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$certPath = Join-Path $projectRoot "certs\server.crt"

if (-not (Test-Path $certPath)) {
    throw "Certificate not found at $certPath. Start docker-compose-selfsigned.yml first."
}

Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Write-Host "Imported self-signed certificate into CurrentUser\\Root: $certPath"
