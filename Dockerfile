FROM lumax_core:latest as lumax-runner

WORKDIR /app
COPY requirements_lumax.txt .
# Install main requirements using the existing environment from donor
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install -r requirements_lumax.txt \
    && python -m pip install pypinyin jieba unidecode num2words cutlet hangul_romanize jamo g2pkk mecab-python3 unidic-lite

# Install llama-cpp-python with CUDA support using PRE-BUILT WHEELS to save user data
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124

# Force ORT GPU upgrade
RUN --mount=type=cache,target=/root/.cache/pip \
    rm -rf /usr/local/lib/python3.11/dist-packages/onnxruntime* && \
    python -m pip install onnxruntime-gpu==1.18.0 --extra-index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-12/pypi/simple/

# Remove shadowed files from donor
RUN rm -f /app/body_interface.py /app/MindCore.py /app/compagent.py || true

COPY ./Backend/Mind /app/mind
COPY ./Backend/Body /app/body
EXPOSE 8000 8001 8002
CMD ["python", "/app/mind/Cognition/compagent.py"]
