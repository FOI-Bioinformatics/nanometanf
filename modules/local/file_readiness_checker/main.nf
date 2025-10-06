process FILE_READINESS_CHECKER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(file)
    val(stability_time)  // Time in seconds file must remain stable

    output:
    tuple val(meta), path(file), env(READY_STATUS), emit: checked_file
    path "versions.yml"                            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def stability_seconds = stability_time ?: 5
    """
    #!/usr/bin/env python3
    import os
    import sys
    import time
    from pathlib import Path

    file_path = Path("${file}")
    stability_time = ${stability_seconds}

    def check_file_stability(path, wait_time=5):
        """
        Check if file is stable (not being written to).
        Returns True if file size hasn't changed for wait_time seconds.
        """
        if not path.exists():
            return False, "File does not exist"

        try:
            # Check if file is locked (try to open for reading)
            with open(path, 'rb') as f:
                # Get initial size
                initial_size = path.stat().st_size
                initial_mtime = path.stat().st_mtime

                # Wait for stability period
                time.sleep(wait_time)

                # Check if size/mtime changed
                final_size = path.stat().st_size
                final_mtime = path.stat().st_mtime

                if initial_size != final_size or initial_mtime != final_mtime:
                    return False, f"File still being written (size: {initial_size} -> {final_size})"

                # Verify file has content
                if final_size == 0:
                    return False, "File is empty"

                return True, f"File is stable ({final_size} bytes)"

        except (IOError, PermissionError) as e:
            return False, f"File is locked or inaccessible: {e}"

    # Check file readiness
    is_ready, message = check_file_stability(file_path, stability_time)

    if is_ready:
        print(f"✓ READY: {file_path.name} - {message}", file=sys.stderr)
        ready_status = "READY"
    else:
        print(f"⏳ NOT_READY: {file_path.name} - {message}", file=sys.stderr)
        ready_status = "NOT_READY"

    # Export status for Nextflow
    with open(os.environ.get('NXF_TASK_WORKDIR', '.') + '/.command.env', 'w') as f:
        f.write(f"READY_STATUS={ready_status}\\n")

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    echo "READY_STATUS=READY" > .command.env

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
