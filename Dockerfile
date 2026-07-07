FROM node:24-slim

ARG HERMES_UID
ARG HERMES_GID

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/home/hermes/.local/bin:/usr/local/bin:$PATH \
    HOME=/home/hermes

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      python3 \
      python3-venv \
      python3-pip \
      python-is-python3 \
      ripgrep \
      ffmpeg \
      build-essential \
      bash && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd --force --gid ${HERMES_GID} hermes; \
    if ! id -u hermes > /dev/null 2>&1; then \
        useradd --uid ${HERMES_UID} --gid ${HERMES_GID} --shell /bin/bash --create-home hermes; \
    fi

# Install uv as root so it's available system-wide
RUN mkdir -p /opt/hermes /home/hermes/.local/bin /home/hermes/.hermes /home/hermes/workspace && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    chown -R hermes:hermes /opt/hermes /home/hermes

# Install Hermes Agent. Use HERMES_HOME=/opt/hermes so the code lives
# at /opt/hermes/hermes-agent/, separate from the runtime data volume.
USER hermes
WORKDIR /home/hermes
ENV HERMES_HOME=/opt/hermes
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

COPY --chown=hermes:hermes scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-lc", "hermes gateway run"]
