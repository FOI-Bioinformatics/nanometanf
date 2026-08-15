#!/usr/bin/env bash
#
# run-nf-tests.sh -- nf-test wrapper for nanometanf.
#
# What it does
# ------------
# 1. Exports NXF_OFFLINE=true to keep the nf-test runtime self-contained
#    once jars are cached.
# 2. Forwards every argument verbatim to nf-test.
#
# History
# -------
# Earlier revisions pinned NXF_VER=25.04.7 to dodge the watchPath /
# FileAlterationMonitor JVM cleanup hang that bit Nextflow 25.10.x
# (task #26). The hang no longer reproduces under Nextflow 26.04.0,
# and the pipeline has been ported to the Nextflow 26 strict v2 grammar,
# so NXF_SYNTAX_PARSER=v1 is no longer required either.
#
# Usage
# -----
#   bin/run-nf-tests.sh test --profile test
#   bin/run-nf-tests.sh test subworkflows/local/realtime_monitoring/...
#
# Override the env var by exporting it before invocation; the wrapper
# only sets a default and does not clobber an explicit caller value.
#
set -euo pipefail

: "${NXF_OFFLINE:=true}"
export NXF_OFFLINE

if ! command -v nf-test >/dev/null 2>&1; then
    echo "run-nf-tests.sh: nf-test not found on PATH" >&2
    echo "run-nf-tests.sh: activate the nf-core conda environment first" >&2
    exit 127
fi

echo "run-nf-tests.sh: NXF_OFFLINE=${NXF_OFFLINE}" >&2
exec nf-test "$@"
