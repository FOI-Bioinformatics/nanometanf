#!/bin/bash
# Quick test runner for nanometanf
# Usage: ./tests/run_tests.sh [fast|core|medium|full|<tag>]
#
# Environment variables:
#   NFT_SHARD  - Run a specific shard for CI parallelism (e.g. "1/4")

set -euo pipefail

export JAVA_HOME="${CONDA_PREFIX}/lib/jvm"
export PATH="${JAVA_HOME}/bin:${PATH}"

TAG="${1:-fast}"
SHARD_ARGS=""
if [ -n "${NFT_SHARD:-}" ]; then
    SHARD_ARGS="--shard ${NFT_SHARD}"
fi

case "$TAG" in
    fast)   nf-test test --tag fast $SHARD_ARGS ;;
    core)   nf-test test --tag core $SHARD_ARGS ;;
    medium) nf-test test --tag fast --tag medium $SHARD_ARGS ;;
    full)   nf-test test $SHARD_ARGS ;;
    *)      nf-test test --tag "$TAG" $SHARD_ARGS ;;
esac
