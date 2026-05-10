#!/usr/bin/env bash
#
# run-nf-tests.sh -- nf-test wrapper for nanometanf.
#
# What it does
# ------------
# 1. Exports NXF_SYNTAX_PARSER=v1 so the pipeline parses under
#    Nextflow >= 26.04.0. The strict v2 grammar introduced in 26
#    rejects the legacy Groovy idioms still present in several
#    subworkflows (C-style for-loops in realtime_monitoring,
#    switch/case in qc_analysis/assembly/taxonomic_classification,
#    "${projectDir}" interpolation in include paths). Porting those
#    is tracked separately; until then, v1 keeps the existing code
#    runnable.
# 2. Exports NXF_OFFLINE=true to keep the nf-test runtime
#    self-contained once jars are cached.
# 3. Forwards every argument verbatim to nf-test.
#
# History
# -------
# Earlier revisions pinned NXF_VER=25.04.7 to dodge the watchPath /
# FileAlterationMonitor JVM cleanup hang that bit Nextflow 25.10.x
# (task #26). Verification under 26.04.0 + NXF_SYNTAX_PARSER=v1 ran
# realtime nf-tests through the full failure path in 55 s with no
# leaked thread, so the pin has been removed and the floor bumped
# to >= 26.04.0 in nextflow.config.
#
# Usage
# -----
#   bin/run-nf-tests.sh test --profile test
#   bin/run-nf-tests.sh test subworkflows/local/realtime_monitoring/...
#
# Override either env var by exporting it before invocation; the
# wrapper only sets defaults and does not clobber explicit values.
#
set -euo pipefail

: "${NXF_SYNTAX_PARSER:=v1}"
: "${NXF_OFFLINE:=true}"
export NXF_SYNTAX_PARSER NXF_OFFLINE

if ! command -v nf-test >/dev/null 2>&1; then
    echo "run-nf-tests.sh: nf-test not found on PATH" >&2
    echo "run-nf-tests.sh: activate the nf-core conda environment first" >&2
    exit 127
fi

echo "run-nf-tests.sh: NXF_SYNTAX_PARSER=${NXF_SYNTAX_PARSER} NXF_OFFLINE=${NXF_OFFLINE}" >&2
exec nf-test "$@"
