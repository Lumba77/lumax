# Build lumax_unified (lumax_soul) with BuildKit + on-disk cache so the CUDA llama-cpp-python
# wheel is downloaded once and reused on later rebuilds.
# Run from repo root:  .\build_lumax_unified.ps1
# Requires: Docker Desktop with BuildKit (default). Optional: $env:DOCKER_BUILDKIT_CACHE = "D:\path\to\cache"

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$env:DOCKER_BUILDKIT = "1"
$cacheDir = if ($env:DOCKER_BUILDKIT_CACHE) { $env:DOCKER_BUILDKIT_CACHE } else { Join-Path $PSScriptRoot "build\docker-buildkit-cache" }
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
if (-not $env:DOCKER_BUILDKIT_CACHE) {
    $env:DOCKER_BUILDKIT_CACHE = $cacheDir
}

Write-Host "BuildKit cache: $env:DOCKER_BUILDKIT_CACHE"
docker compose build lumax_soul @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Done. Next: docker compose up -d lumax_soul"
