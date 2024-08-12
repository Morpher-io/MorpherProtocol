# syntax=docker/dockerfile:1.4


FROM --platform=linux/amd64 ghcr.io/foundry-rs/foundry as build-environment 


FROM --platform=linux/amd64 public.ecr.aws/docker/library/node:22-alpine

RUN apk add --no-cache linux-headers git curl jq bash

COPY --from=build-environment /usr/local/bin/forge /usr/local/bin/forge
COPY --from=build-environment /usr/local/bin/cast /usr/local/bin/cast
COPY --from=build-environment /usr/local/bin/anvil /usr/local/bin/anvil
COPY --from=build-environment /usr/local/bin/chisel /usr/local/bin/chisel

WORKDIR /anvil 
COPY . .



CMD /anvil/helpers/chainfork/start.sh