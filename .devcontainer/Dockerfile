FROM debian:trixie-slim

# Install sudo and create a non-root user for .devcontainer usage
ARG USERNAME=vscode
ARG UID=1001
ARG GID=1001

# créer groupe et utilisateur, installer sudo et autoriser sudo sans mot de passe
RUN groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && apt-get update -y \
    && apt-get install -y sudo \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}


# Install system dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    zip \
    unzip \
    curl \
    jq \
    dnsutils \
    postgresql-client \
    locales \
    wget \
    build-essential \
    procps \
    iproute2 \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Go, matching the toolchain version pinned in go.work
ARG GO_VERSION=1.25.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

RUN npx playwright install --with-deps chromium

# Set the locale
RUN sed -i '/fr_FR.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG=fr_FR.UTF-8
ENV LANGUAGE=fr_FR:fr
ENV LC_ALL=fr_FR.UTF-8

# basculer vers l'utilisateur non-root pour la CMD
USER ${USERNAME}
WORKDIR /workspace

ENV PATH="/usr/local/go/bin:/home/${USERNAME}/go/bin:/home/vscode/.local/bin:${PATH}:/workspace/scripts:/workspace/bin"

# Login shells (bash -l) reset PATH via /etc/profile, dropping the ENV above —
# restore it via profile.d so both login and non-login shells see the same PATH.
USER root
RUN echo 'export PATH="/usr/local/go/bin:/home/'"${USERNAME}"'/go/bin:/home/'"${USERNAME}"'/.local/bin:${PATH}:/workspace/scripts:/workspace/bin"' > /etc/profile.d/workspace-path.sh \
    && chmod 644 /etc/profile.d/workspace-path.sh
USER ${USERNAME}

EXPOSE 8000
EXPOSE 8080
EXPOSE 8081
EXPOSE 5173

# Keep container running; the workspace is mounted at runtime
CMD ["sleep", "infinity"]
