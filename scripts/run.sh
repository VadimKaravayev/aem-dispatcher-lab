#!/bin/bash
cd "$(dirname "$0")/.." && REWRITE_LOG_LEVEL="${REWRITE_LOG_LEVEL:-warn}" DISP_LOG_LEVEL="${DISP_LOG_LEVEL:-warn}" \
sdk/bin/docker_run_hot_reload.sh "$PWD/src" host.docker.internal:4503 8080
