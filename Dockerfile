# Claude Code + JetBrains Runtime (JBR) + HotswapAgent (always on) + Python
FROM node:20-bookworm

# ---- JBR pins ---------------------------------------------------------------
ARG JBR_VERSION=21.0.9
ARG JBR_BUILD=b895.149
ARG JBR_FLAVOR=jbr
ARG JBR_BASE_URL=https://cache-redirector.jetbrains.com/intellij-jbr

# ---- HotswapAgent pin (Maven Central) ---------------------------------------
ARG HOTSWAP_AGENT_VERSION=2.0.2

RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client ca-certificates ripgrep \
    curl bash xz-utils unzip \
    python3 python3-pip python3-venv \
    iproute2 gosu \
  && rm -rf /var/lib/apt/lists/*

# ---- Install JetBrains Runtime ----------------------------------------------
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      arm64)  JBR_ARCH="aarch64" ;; \
      amd64)  JBR_ARCH="x64" ;; \
      *)      echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    FILE="${JBR_FLAVOR}-${JBR_VERSION}-linux-${JBR_ARCH}-${JBR_BUILD}.tar.gz"; \
    URL="${JBR_BASE_URL}/${FILE}"; \
    echo "Downloading: $URL"; \
    mkdir -p /opt/jbr; \
    curl -fL "$URL" -o /tmp/jbr.tar.gz; \
    tar -xzf /tmp/jbr.tar.gz -C /opt/jbr --strip-components=1; \
    rm -f /tmp/jbr.tar.gz; \
    /opt/jbr/bin/java -version

ENV JAVA_HOME=/opt/jbr
ENV PATH="$JAVA_HOME/bin:$PATH"

# ---- Install HotswapAgent ---------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/jbr/lib/hotswap; \
    curl -fL \
      "https://repo1.maven.org/maven2/org/hotswapagent/hotswap-agent/${HOTSWAP_AGENT_VERSION}/hotswap-agent-${HOTSWAP_AGENT_VERSION}.jar" \
      -o /opt/jbr/lib/hotswap/hotswap-agent.jar

# HotSwap always on (JBR 17/21 line)
ENV JAVA_TOOL_OPTIONS="-XX:+AllowEnhancedClassRedefinition -XX:HotswapAgent=fatjar"

# ---- Claude Code ------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code \
  && npm cache clean --force

# ---- Non-root user ----------------------------------------------------------
RUN useradd -m -s /bin/bash dev \
  && mkdir -p /work \
  && chown -R dev:dev /work /home/dev

# ---- Entrypoint (adds host.local for accessing host services) ---------------
RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

# Add host.local pointing to the gateway (host machine)
GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
if [ -n "$GATEWAY_IP" ]; then
  grep -q "host.local" /etc/hosts 2>/dev/null || echo "$GATEWAY_IP host.local" >> /etc/hosts
fi

# If running as root (e.g., -u 0 for maintenance), stay as root
# Otherwise drop to dev user
if [ "$(id -u)" = "0" ] && [ "${STAY_ROOT:-}" != "1" ]; then
  exec gosu dev "$@"
else
  exec "$@"
fi
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENV HOME=/home/dev

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
