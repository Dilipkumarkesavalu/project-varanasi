# syntax=docker/dockerfile:1.7
# Varanasi backend image (M1-FOU-006).
# - Python and uv versions are pinned; Python packages come only from uv.lock (--locked).
# - The final image has no build tools, no dev dependencies and runs as a non-root user.

ARG PYTHON_IMAGE=python:3.13.15-slim-trixie

FROM astral/uv:0.12.19 AS uv

# ---------------------------------------------------------------- build
FROM ${PYTHON_IMAGE} AS build
COPY --from=uv /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /src

# Dependencies first (cached layer), then the project itself.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY README.md alembic.ini ./
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# ---------------------------------------------------------------- runtime
FROM ${PYTHON_IMAGE} AS runtime
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    VARANASI_LOG_FORMAT=json

RUN groupadd --system --gid 10001 varanasi \
 && useradd --system --uid 10001 --gid varanasi --no-create-home --shell /usr/sbin/nologin varanasi

WORKDIR /app
# Owned by root and read-only for the app user: the process cannot modify its own code.
COPY --from=build /app/.venv /app/.venv
COPY --from=build /src/alembic.ini /app/alembic.ini

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status != 200)"]

CMD ["uvicorn", "varanasi.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
