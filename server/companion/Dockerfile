# OneDay Companion - single container hosting the five bridge modules,
# the supervisor (PID 1) and the panel front. Base image is the pinned
# Hermes image: write-gate imports Hermes code from /opt/hermes and the
# box module uses the image venv's MCP SDK - both proven on this image.
FROM nousresearch/hermes-agent:v0.23.0

ARG COMPANION_VERSION=1.0.77
ARG COMPANION_BUILD_DATE=""
ENV COMPANION_VERSION=${COMPANION_VERSION} \
    COMPANION_API_LEVEL=1 \
    COMPANION_BUILD_DATE=${COMPANION_BUILD_DATE} \
    COMPANION_STATE_DIR=/opt/companion-state \
    COMPANION_ENV_FILE=/opt/companion/companion.env \
    COMPANION_PYTHON=/opt/hermes/.venv/bin/python3 \
    TZ=Asia/Shanghai

COPY supervisor/ /opt/companion/supervisor/
COPY front/ /opt/companion/front/
COPY modules/ /opt/companion/modules/
COPY companion.env.example /opt/companion/companion.env.example

# pywinrm (pinned) - full-strength WinRM credential proof for the
# windows-login connection path (cloudpc closeout spec section 4/6).
# The base image venv ships no pip; uv lives under /opt/hermes/tools.
RUN UV_BIN=$(ls /opt/hermes/tools/uv-*/uv | head -1) && \
    "$UV_BIN" pip install --python /opt/hermes/.venv/bin/python3 \
        --no-cache "pywinrm==0.5.0"

# Ports are container-side only; the compose file binds them to the
# host loopback. 8651 (supervisor control channel) is never published.
EXPOSE 8647 8648 8650

ENTRYPOINT ["/opt/hermes/.venv/bin/python3", "/opt/companion/supervisor/supervisor.py"]
