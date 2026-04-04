FROM elixir:1.18

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      inotify-tools \
      ssh-client && \
    rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /workspace
