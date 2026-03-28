FROM elixir:1.18 AS build

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

RUN mix assets.deploy && mix release

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends libssl3 libncurses6 locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
COPY --from=build /app/_build/prod/rel/thermal_print_server ./

ENV PHX_SERVER=true
EXPOSE 4000

CMD ["bin/thermal_print_server", "start"]
