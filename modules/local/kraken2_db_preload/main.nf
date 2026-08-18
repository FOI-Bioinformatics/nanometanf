/*
 * KRAKEN2_DB_PRELOAD
 *
 * Preloads the Kraken2 database hash file into the OS page cache.
 * When memory-mapping is enabled, subsequent Kraken2 processes share
 * the cached pages rather than each loading the database independently.
 * This reduces total memory consumption and speeds up classification
 * start time for all parallel forks.
 *
 * Runs once before any classification begins. The database path is
 * passed through as output for channel wiring.
 */
process KRAKEN2_DB_PRELOAD {
    tag "db_preload"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/coreutils:9.5' :
        'quay.io/biocontainers/coreutils:9.5' }"

    input:
    path db

    output:
    path db, emit: db
    path "preload_status.txt", emit: status
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/bin/bash
    set -euo pipefail

    echo "Preloading Kraken2 database into OS page cache..." >&2

    # Size guard: preloading a database the page cache cannot hold is pure
    # churn -- the OS evicts pages as fast as dd loads them, so the read
    # costs minutes and warms nothing. Skip when hash.k2d exceeds 70% of
    # available memory. MemAvailable is the honest figure on Linux; macOS
    # has no equivalent, so total RAM stands in (an over-estimate, which
    # only errs toward preloading -- the harmless direction).
    if [ -f "${db}/hash.k2d" ]; then
        hash_bytes=\$(wc -c < "${db}/hash.k2d" | tr -d ' ')
        avail_bytes=""
        if [ -r /proc/meminfo ]; then
            avail_bytes=\$(awk '/^MemAvailable:/ {print \$2 * 1024}' /proc/meminfo)
        elif command -v sysctl >/dev/null 2>&1; then
            avail_bytes=\$(sysctl -n hw.memsize 2>/dev/null || true)
        fi

        if [ -n "\$avail_bytes" ] && [ "\$hash_bytes" -gt \$(( avail_bytes * 70 / 100 )) ]; then
            echo "skipped: hash.k2d (\$(( hash_bytes / 1024 / 1024 / 1024 )) GiB) exceeds 70% of available memory (\$(( avail_bytes / 1024 / 1024 / 1024 )) GiB)" > preload_status.txt
            echo "Database exceeds available memory; skipping preload (pages would be evicted as fast as they load)" >&2
        else
            dd if="${db}/hash.k2d" of=/dev/null bs=1M 2>&1 | tail -1 >&2
            # Also preload the taxonomy files (smaller, but accessed by
            # every process)
            for f in "${db}/taxo.k2d" "${db}/opts.k2d"; do
                if [ -f "\$f" ]; then
                    dd if="\$f" of=/dev/null bs=1M 2>/dev/null || true
                fi
            done
            echo "preloaded: \$(( hash_bytes / 1024 / 1024 )) MiB warmed into the page cache" > preload_status.txt
            echo "Database preload complete" >&2
        fi
    else
        echo "skipped: hash.k2d not found in database directory" > preload_status.txt
        echo "Warning: hash.k2d not found in database directory, skipping preload" >&2
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dd: \$(dd --version 2>&1 | head -1 || echo "built-in")
    END_VERSIONS
    """

    stub:
    """
    echo "preloaded: stub" > preload_status.txt
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dd: built-in
    END_VERSIONS
    """
}
