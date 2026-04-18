# NOTE: use Google's "distroless with libgcc1" base image, see:
#       https://github.com/GoogleContainerTools/distroless/blob/6755e21ccd99ddead6edc8106ba03888cbeed41a/cc/README.md
ARG BASE_IMAGE_FINAL_STAGES="gcr.io/distroless/cc:nonroot"

FROM rust:1-bookworm AS builder

WORKDIR /usr/src/lidi
COPY . .
# Use host networking for this step so cargo can reach index.crates.io.
# Required when Docker's default bridge cannot resolve external DNS — e.g. on
# Arch where systemd-resolved's stub at 127.0.0.53 is unreachable from the
# build sandbox. Requires a buildx builder with the `network.host` entitlement
# (see doc/RUNBOOK.md). Runtime images are unaffected.
RUN --network=host cargo install --locked --path .

FROM ${BASE_IMAGE_FINAL_STAGES} AS send

COPY --from=builder --chown=root:root --chmod=755 /usr/local/cargo/bin/diode-send /usr/local/bin/
ENTRYPOINT ["diode-send"]

FROM ${BASE_IMAGE_FINAL_STAGES} AS receive

COPY --from=builder --chown=root:root --chmod=755 /usr/local/cargo/bin/diode-receive /usr/local/bin/
ENTRYPOINT ["diode-receive"]