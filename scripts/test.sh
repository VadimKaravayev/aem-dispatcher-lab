#!/bin/bash
cd "$(dirname "$0")/.." && sdk/bin/docker_run.sh "$PWD/src" localhost:4503 test
