# syntax=docker/dockerfile:1
#
# spoolman-railway: thin wrapper around the official Spoolman image.
#
# Spoolman has no authentication -- upstream says so in spoolman/security.py: "Spoolman has no
# authentication by design; the boundary that protects a user's data is the network." Railway hands
# every service a public URL, which removes that boundary, so this wrapper supplies one: Caddy
# fronts the app with HTTP basic authentication and Spoolman itself is bound to loopback, where
# nothing outside the container can reach it. Application code is unchanged.
#
# Both images are pinned by tag AND digest. Update the image and version args together.
ARG CADDY_IMAGE=docker.io/library/caddy:2.10-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
ARG SPOOLMAN_IMAGE=ghcr.io/donkie/spoolman:0.26.1@sha256:cf9b41e17b93ce7d4ca584d9809142f8918fd290f2cd7d3b8b12ff76c75482f0

FROM ${CADDY_IMAGE} AS caddy

FROM ${SPOOLMAN_IMAGE}

ARG SPOOLMAN_VERSION=0.26.1
ARG CADDY_VERSION=2.10.2
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root

# Caddy ships as a static Go binary, so the alpine-built one runs on this Debian base unchanged.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY licenses/ /usr/share/licenses/spoolman-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/spoolman-railway-entrypoint
RUN caddy version \
    && install -d -o app -g app /etc/spoolman-railway

ENV SPOOLMAN_HOST=127.0.0.1 \
    SPOOLMAN_INTERNAL_PORT=8765 \
    SPOOLMAN_AUTH_USERNAME=admin

LABEL org.opencontainers.image.title="spoolman-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Spoolman, the 3D-printer filament inventory. Adds authentication. Not affiliated with the Spoolman project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/spoolman-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/spoolman-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/spoolman-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="ghcr.io/donkie/spoolman:${SPOOLMAN_VERSION}" \
      io.spoolman-railway.upstream.version="${SPOOLMAN_VERSION}" \
      io.spoolman-railway.caddy.version="${CADDY_VERSION}"

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/spoolman-railway-entrypoint"]
