FROM python:3.12-slim

WORKDIR /app
COPY sidecar /app/sidecar

RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && pip install --no-cache-dir /app/sidecar

ENV HF_HOME=/models/huggingface
EXPOSE 9090
CMD ["uvicorn", "sidecar.app:app", "--host", "0.0.0.0", "--port", "9090"]
