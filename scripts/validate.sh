#!/bin/bash
cd "$(dirname "$0")/.." && sdk/bin/validate.sh "$PWD/src"
