# Claude Code + JetBrains Runtime (JBR) + HotswapAgent (always on) + Python
FROM node:20-bookworm-slim

# ---- JBR pins ---------------------------------------------------------------
ARG JBR_VERSION=21.0.9
ARG JBR_BUILD=b895.149
ARG JBR_FLAVOR=jbr
ARG JBR_BASE_URL=https://cache-redirector.jetbrains.com/intellij-jbr

# ---- HotswapAgent pin (Maven Central) ---------------------------------------
ARG HOTSWAP_AGENT_VERSION=2.0.2

# ---- Eclipse JDT Language Server pin ----------------------------------------
ARG JDTLS_VERSION=1.40.0
ARG JDTLS_TIMESTAMP=202409261450

RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client ca-certificates ripgrep \
    curl bash xz-utils unzip \
    python3 python3-pip python3-venv \
    iproute2 gosu socat maven \
    # Playwright/Chromium dependencies (replaces npx playwright install-deps)
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
    libcups2 libdbus-1-3 libdrm2 libgbm1 libgtk-3-0 \
    libnspr4 libnss3 libpango-1.0-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxkbcommon0 libxrandr2 xvfb \
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

# ---- HotswapAgent global configuration --------------------------------------
RUN cat <<'EOF' > /opt/jbr/lib/hotswap/hotswap-agent.properties
# Auto-swap classes without requiring debug mode
autoHotswap=true

# Watch for class changes in common locations
extraClasspath=target/classes

# Disable plugins that add overhead (keep Spring, Vaadin, Proxy, AnonymousClassPatch)
disabledPlugins=Hibernate,Logback,Log4j2,Weld,Deltaspike,WebObjects,WildFlyELResolver,MyFaces,OmniFaces,Mojarra,Resteasy,Jersey

# Vaadin specific: reduce browser refresh delay
vaadin.liveReloadQuietTime=500
EOF

# HotSwap always on (JBR 17/21 line)
ENV JAVA_TOOL_OPTIONS="-XX:+AllowEnhancedClassRedefinition -XX:HotswapAgent=fatjar -Dvaadin.productionMode=false -Dspring.devtools.restart.enabled=false"

# ---- Eclipse JDT Language Server (jdtls) ------------------------------------
RUN set -eux; \
    mkdir -p /opt/jdtls; \
    curl -fL \
      "https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_TIMESTAMP}.tar.gz" \
      -o /tmp/jdtls.tar.gz; \
    tar -xzf /tmp/jdtls.tar.gz -C /opt/jdtls; \
    rm -f /tmp/jdtls.tar.gz; \
    ln -s /opt/jdtls/bin/jdtls /usr/local/bin/jdtls

# ---- Claude Code + Language Servers + AI CLIs ------------------------------
RUN npm install -g \
    @anthropic-ai/claude-code \
    @google/gemini-cli \
    @openai/codex \
    typescript \
    typescript-language-server \
    pyright \
  && npm cache clean --force

# ---- Mistral Vibe (requires Python 3.12+, use uv for version management) ---
ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && /root/.local/bin/uv tool install mistral-vibe --python 3.12 \
  && chmod -R a+rX /opt/uv-tools /opt/uv-python

# ---- Playwright browser (build-time install for reliability) ----------------
# Install Chromium to a fixed location instead of user cache for container use
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx playwright install chromium

# ---- Chrome wrapper for Playwright MCP compatibility ------------------------
# When projects use @playwright/mcp without --browser flag, it looks for Chrome.
# This wrapper redirects to our installed Playwright Chromium.
RUN mkdir -p /opt/google/chrome && cat <<'EOF' > /opt/google/chrome/chrome
#!/bin/bash
exec /ms-playwright/chromium-*/chrome-linux/chrome "$@"
EOF
RUN chmod +x /opt/google/chrome/chrome

# ---- Non-root user ----------------------------------------------------------
RUN useradd -m -s /bin/bash dev \
  && mkdir -p /work \
  && chown -R dev:dev /work /home/dev /ms-playwright

# ---- Entrypoint (host.local setup + path parity) ---------------------------
RUN cat <<'EOF' > /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

export JAVA_HOME=/opt/jbr
export PATH="$JAVA_HOME/bin:$PATH"

# Add host.local pointing to host machine
# Docker Desktop (macOS/Windows): use host.docker.internal
# Apple Containers / Docker on Linux: use gateway IP
if getent ahostsv4 host.docker.internal >/dev/null 2>&1; then
  HOST_IP=$(getent ahostsv4 host.docker.internal | head -1 | awk '{print $1}')
else
  HOST_IP=$(ip route | grep default | awk '{print $3}')
fi
if [ -n "$HOST_IP" ]; then
  grep -q "host.local" /etc/hosts 2>/dev/null || echo "$HOST_IP host.local" >> /etc/hosts
fi

# Forward host ports to container localhost (for MCPs that expect localhost)
if [ -n "${HOST_FORWARD_PORTS:-}" ]; then
  IFS=',' read -ra PORTS <<< "$HOST_FORWARD_PORTS"
  for mapping in "${PORTS[@]}"; do
    if [[ "$mapping" == *:* ]]; then
      local_port="${mapping%%:*}"
      host_port="${mapping##*:}"
    else
      local_port="$mapping"
      host_port="$mapping"
    fi
    socat TCP-LISTEN:${local_port},fork,reuseaddr TCP:host.local:${host_port} &
  done
fi

# Path parity setup: match host HOME and UID/GID
if [ -n "${HOST_HOME:-}" ]; then
  mkdir -p "${HOST_HOME}"

  # Match host UID/GID (handle conflicts)
  if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    EXISTING_GROUP=$(getent group "${HOST_GID}" | cut -d: -f1)
    if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "dev" ]; then
      groupmod -g $((HOST_GID + 10000)) "$EXISTING_GROUP" 2>/dev/null || true
    fi

    EXISTING_USER=$(getent passwd "${HOST_UID}" | cut -d: -f1)
    if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "dev" ]; then
      usermod -u $((HOST_UID + 10000)) "$EXISTING_USER" 2>/dev/null || true
    fi

    groupmod -g "${HOST_GID}" dev 2>/dev/null || true
    usermod -u "${HOST_UID}" -g "${HOST_GID}" -d "${HOST_HOME}" dev 2>/dev/null || true
  fi

  chown dev:dev "${HOST_HOME}" 2>/dev/null || true
  chown -R dev:dev "${HOST_HOME}/.claude" 2>/dev/null || true
  chown -R dev:dev /ms-playwright 2>/dev/null || true

  export HOME="${HOST_HOME}"

  # Create container-side symlink to ~/.claude.json in shared directory
  # (Apple Containers can't bind-mount individual files, so we use symlinks)
  SHARED_CLAUDE_JSON="${HOST_HOME}/.claude-contained/.claude.json"
  if [ -e "${SHARED_CLAUDE_JSON}" ] && [ ! -e "${HOST_HOME}/.claude.json" ]; then
    ln -s "${SHARED_CLAUDE_JSON}" "${HOST_HOME}/.claude.json"
    chown -h dev:dev "${HOST_HOME}/.claude.json" 2>/dev/null || true
  fi

  # Copy .gitconfig for git commit identity (read-only, no sync back needed)
  SHARED_GITCONFIG="${HOST_HOME}/.claude-contained/.gitconfig"
  if [ -e "${SHARED_GITCONFIG}" ] && [ ! -e "${HOST_HOME}/.gitconfig" ]; then
    cp "${SHARED_GITCONFIG}" "${HOST_HOME}/.gitconfig"
    chown dev:dev "${HOST_HOME}/.gitconfig" 2>/dev/null || true
  fi
fi

# Drop to dev user (or stay root if STAY_ROOT=1)
if [ "$(id -u)" = "0" ] && [ "${STAY_ROOT:-}" != "1" ]; then
  exec gosu dev env \
    JAVA_HOME="$JAVA_HOME" \
    PATH="$PATH" \
    HOME="${HOME:-/home/dev}" \
    "$@"
else
  exec "$@"
fi
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
# HOME is set dynamically in entrypoint based on HOST_HOME

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
