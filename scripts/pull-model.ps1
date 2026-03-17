$ErrorActionPreference = "Stop"

param(
    [string]$Model = $env:OLLAMA_DEFAULT_MODEL
)

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = "llama3.2"
}

$ollamaApiBase = $env:OLLAMA_API_BASE

if ([string]::IsNullOrWhiteSpace($ollamaApiBase) -or $ollamaApiBase -eq "http://ollama:11434") {
    docker compose exec ollama ollama pull $Model
    exit $LASTEXITCODE
}

$ollamaCommand = Get-Command ollama -ErrorAction SilentlyContinue

if ($null -eq $ollamaCommand) {
    throw "OLLAMA_API_BASE points to a host Ollama instance, but the 'ollama' CLI was not found on the host. Install Ollama locally or switch OLLAMA_API_BASE back to http://ollama:11434."
}

ollama pull $Model
