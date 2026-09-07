FROM python:3.12.13-slim-bookworm
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 OMR_ENV=production OMR_DATA_DIR=/data \
    OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=4
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git libglib2.0-0 libgl1 libgomp1 openssl ca-certificates gosu && rm -rf /var/lib/apt/lists/*
COPY services/omr/requirements-lock.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY services/omr/ ./
RUN chmod +x entrypoint.sh && python patch_homr.py && python models.py --download && python build_source_offer.py && \
    useradd --create-home --uid 10001 stringmap && mkdir -p /data && chown stringmap:stringmap /data
ENTRYPOINT ["/app/entrypoint.sh"]
EXPOSE 8080
# Exactly one process, worker, replica, and persistent /data volume.
CMD ["sh", "-c", "exec uvicorn production:configured_app --factory --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --no-access-log --proxy-headers --forwarded-allow-ips='*'"]
