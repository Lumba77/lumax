FROM ollama/ollama:0.17.1-rc2

# Expose the Ollama port
EXPOSE 11434

# curl for scripts; netcat for Docker healthcheck (TCP-only — avoids Gin HTTP access logs on every probe).
RUN apt-get update && apt-get install -y --no-install-recommends curl netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Pull models after the container is up: see scripts/pull_ollama_backup_models.ps1

# Base image entrypoint is already `ollama`; pass only subcommand.
CMD ["serve"]
