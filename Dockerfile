# The app image: Flask + gunicorn + psycopg2, config via env only.
# Built and pushed by the Jenkins pipeline (Jenkinsfile) on every push;
# on main it also deploys to web1/web2. Manual fallback (repo root is the
# build context now — no app/ path):
#   docker build -t localhost:5000/tiket-app:<tag> .
#   docker login localhost:5000 && docker push localhost:5000/tiket-app:<tag>
FROM python:3.11-slim-bookworm

# Pinned for reproducible rebuilds; bump deliberately.
RUN pip install --no-cache-dir \
        flask==3.1.1 \
        gunicorn==23.0.0 \
        psycopg2-binary==2.9.10


# Version injected by the pipeline (--build-arg APP_VERSION=<branch>-<build>),
# served by the /version endpoint. "dev" fallback for manual builds.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY app.py .

# gunicorn needs no privileges; slim base ships python3, so the healthcheck
# uses stdlib urllib instead of pulling in curl.
RUN useradd --system --uid 1000 app
USER app
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:8000", "app:app"]
