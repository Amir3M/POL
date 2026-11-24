FROM mcr.microsoft.com/devcontainers/java:1-21-bookworm@sha256:0af991049cded4b8d5a90d2614289ceec390779ad6a3e4b70957e2b4f3bb1230

# Flutter's Linux host test engine loads libGL. jq selects the official Go checksum.
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq libgl1 \
    && rm -rf /var/lib/apt/lists/*
