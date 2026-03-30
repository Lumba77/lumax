FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Set WORKDIR directly to /app for simpler module resolution
WORKDIR /app

# Set PYTHONPATH to ensure Python can find modules in /app
ENV PYTHONPATH=/app

# System dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set python3.11 as default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Copy requirements.txt and install dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Copy the rest of the service code
COPY . .

# Expose the port the service runs on
EXPOSE 8004

# Command to run the service
CMD ["python", "creative_service.py"]
