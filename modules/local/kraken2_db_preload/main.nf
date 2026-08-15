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
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/bin/bash
    set -euo pipefail

    echo "Preloading Kraken2 database into OS page cache..." >&2

    # Read hash.k2d into page cache using dd for efficient sequential I/O
    if [ -f "${db}/hash.k2d" ]; then
        dd if="${db}/hash.k2d" of=/dev/null bs=1M 2>&1 | tail -1 >&2
        echo "Database hash file loaded into page cache" >&2
    else
        echo "Warning: hash.k2d not found in database directory, skipping preload" >&2
    fi

    # Also preload the taxonomy files (smaller, but accessed by every process)
    for f in "${db}/taxo.k2d" "${db}/opts.k2d"; do
        if [ -f "\$f" ]; then
            dd if="\$f" of=/dev/null bs=1M 2>/dev/null || true
        fi
    done

    echo "Database preload complete" >&2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dd: \$(dd --version 2>&1 | head -1 || echo "built-in")
    END_VERSIONS
    """

    stub:
    """
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dd: built-in
    END_VERSIONS
    """
}
