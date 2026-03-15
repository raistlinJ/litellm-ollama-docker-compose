$ErrorActionPreference = "Stop"

param(
    [string]$Model = $env:OLLAMA_DEFAULT_MODEL
)

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = "llama3.2"
}

docker compose exec ollama ollama pull $Model
