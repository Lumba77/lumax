FROM nvcr.io/nvidia/pytorch:24.03-py3

# Basic dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11-dev \
    git \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set WORKDIR directly to /app for simpler module resolution
WORKDIR /app

# Set PYTHONPATH to ensure Python can find modules in /app
ENV PYTHONPATH=/app

# Upgrade pip
RUN python -m pip install --upgrade pip

# Copy requirements.txt and install only essential dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Copy the rest of the application code
COPY . .

# Expose the port FastAPI runs on
EXPOSE 8000

# Command to run the FastAPI application
CMD ["python", "-m", "uvicorn", "compagent:app", "--host", "0.0.0.0", "--port", "8000"]
