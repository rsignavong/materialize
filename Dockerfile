# syntax=docker/dockerfile:experimental
FROM rust:1.59-slim-buster AS builder
LABEL maintainer=rsignavong

ARG GITLAB_TOKEN
ARG MZ_DEV_BUILD_SHA
ENV MZ_DEV_BUILD_SHA=$MZ_DEV_BUILD_SHA

RUN apt-get -qy update
RUN apt-get -qy install \
    ca-certificates \
    git \
    g++ \
    make \
    bash \
    cmake \
    openssl 

RUN mkdir -m 700 /root/.ssh; \
  touch -m 600 /root/.ssh/known_hosts; \
  ssh-keyscan github.com > /root/.ssh/known_hosts \
  ssh-keyscan gitlab.com >> /root/.ssh/known_hosts
RUN git config --global credential.helper store
RUN echo "https://rsignavong:${GITLAB_TOKEN}@gitlab.com" > ~/.git-credentials
RUN mkdir -m 700 /root/.cargo; \
  touch -m 600 /root/.cargo/config; \
  echo '[credential]' > /root/.cargo/config; \
  echo 'helper = store' >> /root/.cargo/config; \
  echo '' >> /root/.cargo/config; \
  echo '[net]' >> /root/.cargo/config; \
  echo 'git-fetch-with-cli = true' >> /root/.cargo/config

RUN mkdir -p /app/sources
RUN mkdir -p /app/build
WORKDIR /app/sources

COPY src ./src
COPY demo ./demo
COPY fuzz ./fuzz
COPY play ./play
COPY test ./test
COPY Cargo.lock .
COPY Cargo.toml .
COPY deny.toml .
COPY pyproject.toml .
COPY ci/deploy/website/favicon.ico ./src/materialized/src/http/static/favicon.ico

ENV RUSTFLAGS="-C target-feature=-crt-static"
RUN --mount=type=ssh cargo build --release --target-dir /app/build

FROM rust:1.59-slim-buster

RUN apt-get -qy update
RUN apt-get -qy install \
    ca-certificates \
    curl \
    sqlite3 \
    tini 

RUN mkdir -p /app/mzdata
# COPY --from=builder --chown=nobody:nogroup /app/build/release/materialized /app/materialized
COPY --from=builder /app/build/release/materialized /app/materialized
WORKDIR /app
# RUN chown nobody:nogroup /app/mzdata
VOLUME /app/mzdata
# USER nobody

ENTRYPOINT ["tini", "--", "/app/materialized", "--log-file=stderr", "--listen-addr=0.0.0.0:6875"]


