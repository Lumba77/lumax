FROM lumax_core:latest as lumax-runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    libasound2 portaudio19-dev libgomp1 libgl1 libglib2.0-0 libsndfile1 espeak-ng git \
    cmake build-essential g++ ffmpeg libsndfile1-dev python3.11-dev libportaudio2 && \
    rm -rf /var/lib/apt/lists/*

# Fix symlinks for ONNX Runtime compatibility within the same image
RUN ln -s /usr/local/cuda/lib64/libcublas.so.12 /usr/local/cuda/lib64/libcublas.so.11 && \
    ln -s /usr/local/cuda/lib64/libcublasLt.so.12 /usr/local/cuda/lib64/libcublasLt.so.11 && \
    ln -s /usr/local/cuda/lib64/libcudart.so.12 /usr/local/cuda/lib64/libcudart.so.11 && \
    ln -s /usr/local/cuda/lib64/libcudart.so.12 /usr/local/cuda/lib64/libcudart.so.11.0 && \
    ln -s /usr/local/cuda/lib64/libcufft.so.11 /usr/local/cuda/lib64/libcufft.so.10 && \
    ln -s /usr/local/lib/python3.11/dist-packages/nvidia/cudnn/lib/libcudnn.so.9 /usr/local/cuda/lib64/libcudnn.so.8 && \
    ln -s /usr/local/lib/python3.11/dist-packages/nvidia/cudnn/lib/libcudnn.so.9 /usr/local/cuda/lib64/libcudnn.so.7 || true

ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

WORKDIR /app
COPY requirements_lumax.txt .
# Install main requirements with CUDA support for llama-cpp-python
RUN CMAKE_ARGS="-DLLAMA_CUDA=on" python -m pip install --no-cache-dir -r requirements_lumax.txt

# Force ORT GPU upgrade
RUN rm -rf /usr/local/lib/python3.11/dist-packages/onnxruntime* && \
    python -m pip install --no-cache-dir onnxruntime-gpu==1.18.0 --extra-index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-12/pypi/simple/

# Remove shadowed files from donor
RUN rm -f /app/body_interface.py /app/MindCore.py /app/compagent.py || true

COPY ./Backend/Mind /app/mind
COPY ./Backend/Body /app/body
EXPOSE 8000 8001 8002
CMD ["python", "/app/mind/Cognition/compagent.py"]
