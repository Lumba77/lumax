FROM ollama/ollama:0.17.1-rc2

# Expose the Ollama port
EXPOSE 11434

# Install curl for health checks in the entrypoint
RUN apt-get update && apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Pull models after the container is up: see scripts/pull_ollama_backup_models.ps1

# Base image entrypoint is already `ollama`; pass only subcommand.
CMD ["serve"]
