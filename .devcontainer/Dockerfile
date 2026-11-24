FROM docker.io/library/eclipse-temurin:21-jdk-noble@sha256:dc333cdac241f073941f043792f2a2f9b790bfe7cd98ef2843c08880986708de

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git jq libgl1 sudo unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 may reserve UID 1000 for ubuntu.
RUN if getent passwd ubuntu >/dev/null; then \
        usermod -l vscode -d /home/vscode -m ubuntu \
        && groupmod -n vscode ubuntu; \
    else \
        useradd --create-home --shell /bin/bash --uid 1000 vscode; \
    fi \
    && printf 'vscode ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

USER vscode
