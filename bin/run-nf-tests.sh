#!/usr/bin/env bash
#
# run-nf-tests.sh -- nf-test wrapper that pins the Nextflow runtime
#                    to a release whose post-timeout shutdown path
#                    completes cleanly.
#
# Why this wrapper exists
# -----------------------
# Nextflow 25.10.4 does not release the DirWatcherV2 thread or the
# dataflow network after a real-time timeout sentinel fires. Any
# nf-test that exercises realtime_mode = true therefore hangs
# indefinitely once the run logically completes, because nf-test
# waits for the JVM to exit before reporting success. See task #26
# for the upstream investigation; the workaround lives here until
# the issue is patched upstream.
#
# nf-test 0.9.4 only exposes a minimum-version `requires` clause in
# nf-test.config (no exact-version pin), so the runtime version has
# to be selected via the NXF_VER environment variable. The Nextflow
# launcher script honours NXF_VER by downloading the requested
# release jar on first use and reusing it on subsequent invocations.
#
# Scope of the workaround (cycle 6 / 2026-04-27 verification)
# -----------------------------------------------------------
# The pin to 25.04.7 cleans up after the timeout-fires-first path
# (the audit harness Scenarios B/C/D observed self-termination
# within seconds of the sentinel firing). It does NOT clean up
# after the take-fires-first path: the
# realtime_monitoring/.../task10 nf-test, which terminates via
# .take(max_files) before any timeout fires, still leaves the
# Apache commons-io FileAlterationMonitor running as a non-daemon
# thread under 25.04.7 (verified by jstack). The wrapper is
# therefore not a complete fix for #26, but it is still the
# recommended single entry point: it keeps the toolchain
# consistent across operators, lets us flip the pin centrally if
# upstream resolves the issue, and stays harmless for the
# non-realtime tests that make up the bulk of the suite.
#
# Cycle 9 (2026-04-26) tagged the two affected nf-tests (the
# realtime_mode = true cases in
# subworkflows/local/realtime_monitoring/tests/main.nf.test) with
# "hangs-on-jvm-cleanup" so they can be located mechanically.
# nf-test 0.9.4 does not provide an --exclude-tag flag (only an
# inclusive --tag), so the tag is currently advisory: operators
# running the whole suite should omit the realtime_monitoring test
# file from the path arguments until upstream lands a fix. The
# upstream-issue text and the jstack capture used to file the
# upstream report live in
# docs/upstream-issues/26-watchpath-cleanup-hang.md.
#
# What it does
# ------------
# 1. Exports NXF_VER=25.04.7 -- the last release whose timeout
#    cleanup completed within seconds of the sentinel firing.
# 2. Exports NXF_OFFLINE=true -- avoids the String.format plugin
#    loader regression that bites on the 25.10 line and keeps the
#    runtime self-contained once jars are cached.
# 3. Forwards every argument verbatim to nf-test, so callers can
#    use the wrapper as a drop-in replacement.
#
# Usage
# -----
#   bin/run-nf-tests.sh test subworkflows/local/realtime_monitoring/...
#   bin/run-nf-tests.sh test --profile test
#
# Override the pinned version (rare) by exporting NXF_VER before
# invocation; the wrapper only sets a default and does not clobber
# an explicit caller value.
#
set -euo pipefail

: "${NXF_VER:=25.04.7}"
: "${NXF_OFFLINE:=true}"
export NXF_VER NXF_OFFLINE

if ! command -v nf-test >/dev/null 2>&1; then
    echo "run-nf-tests.sh: nf-test not found on PATH" >&2
    echo "run-nf-tests.sh: activate the nf-core conda environment first" >&2
    exit 127
fi

echo "run-nf-tests.sh: NXF_VER=${NXF_VER} NXF_OFFLINE=${NXF_OFFLINE}" >&2
exec nf-test "$@"
