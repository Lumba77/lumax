FROM ollama/ollama:0.17.1-rc2

# Expose the Ollama port
EXPOSE 11434

# Install curl for health checks in the entrypoint
RUN apt-get update && apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Models will be pulled on container startup if not present in the volume.
# This Dockerfile only prepares the base Ollama image.

# Command to start the Ollama server
CMD ["ollama", "serve"]
