process AGGREGATE_VALIDATION_RESULTS {
    tag "aggregate"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    path(blast_stats)
    path(minimap2_stats)
    path(extraction_stats)
    val(validation_method)

    output:
    path("validation_results.json"), emit: json
    path("validation_summary.tsv"), emit: summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def pipeline_version = workflow.manifest.version ?: "dev"
    """
    #!/usr/bin/env python3

    import json
    import sys
    from datetime import datetime, timezone
    from pathlib import Path
    from collections import defaultdict

    # Configuration from params
    validation_method = "${validation_method}"
    pipeline_version = "${pipeline_version}"
    hit_threshold = ${params.validation_hit_rate_threshold ?: 0.5}
    identity_threshold = ${params.validation_identity_threshold ?: 90.0}

    # Initialize results structure and failure counters
    results = defaultdict(dict)
    extraction_data = {}
    parse_failures = {'extraction': 0, 'blast': 0, 'minimap2': 0}
    parse_totals = {'extraction': 0, 'blast': 0, 'minimap2': 0}

    # Parse extraction stats first (for kraken_reads counts)
    for f in Path('.').glob('*_extraction_stats.json'):
        parse_totals['extraction'] += 1
        try:
            with open(f) as fh:
                data = json.load(fh)
                sample_id = data.get('sample_id', 'unknown')
                taxid = str(data.get('taxid', 0))
                extraction_data[(sample_id, taxid)] = {
                    'extracted_reads': data.get('extracted_reads', 0),
                    'total_classified_reads': data.get('total_classified_reads', 0)
                }
        except Exception as e:
            parse_failures['extraction'] += 1
            print(f"Warning: Failed to parse {f}: {e}", file=sys.stderr)

    # Parse BLAST stats
    for f in Path('.').glob('*.blast_stats.json'):
        parse_totals['blast'] += 1
        try:
            with open(f) as fh:
                data = json.load(fh)
                sample_id = data.get('sample_id', 'unknown')
                taxid = str(data.get('taxid', 0))

                # Get extraction data for this sample/taxid
                ext_data = extraction_data.get((sample_id, taxid), {})

                results[sample_id][taxid] = {
                    'taxid': int(taxid),
                    'validation_method': 'blast',
                    'kraken_reads': ext_data.get('extracted_reads', data.get('total_reads', 0)),
                    'extracted_reads': ext_data.get('extracted_reads', data.get('total_reads', 0)),
                    'blast_hits': data.get('blast_hits', 0),
                    'hit_rate': data.get('hit_rate', 0.0),
                    'avg_identity': data.get('avg_identity', 0.0),
                    'avg_coverage': data.get('avg_coverage', 0.0),
                    'validation_status': data.get('validation_status', 'unknown')
                }
        except Exception as e:
            parse_failures['blast'] += 1
            print(f"Warning: Failed to parse {f}: {e}", file=sys.stderr)

    # Parse minimap2 stats
    for f in Path('.').glob('*.minimap2_stats.json'):
        parse_totals['minimap2'] += 1
        try:
            with open(f) as fh:
                data = json.load(fh)
                sample_id = data.get('sample_id', 'unknown')
                taxid = str(data.get('taxid', 0))

                # Get extraction data
                ext_data = extraction_data.get((sample_id, taxid), {})

                # If we already have BLAST results, add minimap2 as additional field
                if taxid in results[sample_id]:
                    results[sample_id][taxid]['minimap2_mapped'] = data.get('mapped_reads', 0)
                    results[sample_id][taxid]['minimap2_hit_rate'] = data.get('hit_rate', 0.0)
                    results[sample_id][taxid]['minimap2_identity'] = data.get('avg_identity', 0.0)
                    results[sample_id][taxid]['minimap2_status'] = data.get('validation_status', 'unknown')
                else:
                    results[sample_id][taxid] = {
                        'taxid': int(taxid),
                        'validation_method': 'minimap2',
                        'kraken_reads': ext_data.get('extracted_reads', data.get('total_reads', 0)),
                        'extracted_reads': ext_data.get('extracted_reads', data.get('total_reads', 0)),
                        'mapped_reads': data.get('mapped_reads', 0),
                        'hit_rate': data.get('hit_rate', 0.0),
                        'avg_identity': data.get('avg_identity', 0.0),
                        'avg_coverage': data.get('avg_coverage', 0.0),
                        'avg_mapq': data.get('avg_mapq', 0.0),
                        'validation_status': data.get('validation_status', 'unknown')
                    }
        except Exception as e:
            parse_failures['minimap2'] += 1
            print(f"Warning: Failed to parse {f}: {e}", file=sys.stderr)

    # Report parse failure summary
    total_files = sum(parse_totals.values())
    total_failures = sum(parse_failures.values())
    if total_failures > 0:
        print(f"WARNING: {total_failures}/{total_files} validation stats files failed to parse:", file=sys.stderr)
        for category, count in parse_failures.items():
            if count > 0:
                print(f"  - {category}: {count}/{parse_totals[category]} failed", file=sys.stderr)
    if total_files > 0 and total_failures == total_files:
        print("ERROR: All validation stats files failed to parse - results will be empty!", file=sys.stderr)

    # Calculate summary statistics
    total_samples = len(results)
    total_taxids = sum(len(taxids) for taxids in results.values())
    confirmed = sum(1 for sample in results.values() for r in sample.values() if r.get('validation_status') == 'confirmed')
    uncertain = sum(1 for sample in results.values() for r in sample.values() if r.get('validation_status') == 'uncertain')
    rejected = sum(1 for sample in results.values() for r in sample.values() if r.get('validation_status') == 'rejected')

    # Build final output
    output = {
        'pipeline_version': pipeline_version,
        'validation_method': validation_method,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'thresholds': {
            'hit_rate': hit_threshold,
            'identity': identity_threshold
        },
        'results': dict(results),
        'summary': {
            'total_samples': total_samples,
            'total_taxids_validated': total_taxids,
            'confirmed': confirmed,
            'uncertain': uncertain,
            'rejected': rejected
        }
    }

    # Write JSON output
    with open('validation_results.json', 'w') as out:
        json.dump(output, out, indent=2)

    # Write TSV summary
    with open('validation_summary.tsv', 'w') as out:
        out.write('sample_id\\ttaxid\\tmethod\\tkraken_reads\\thits\\thit_rate\\tavg_identity\\tavg_coverage\\tstatus\\n')
        for sample_id, taxids in results.items():
            for taxid, data in taxids.items():
                method = data.get('validation_method', 'unknown')
                kraken_reads = data.get('kraken_reads', 0)
                hits = data.get('blast_hits', data.get('mapped_reads', 0))
                hit_rate = data.get('hit_rate', 0.0)
                avg_identity = data.get('avg_identity', 0.0)
                avg_coverage = data.get('avg_coverage', 0.0)
                status = data.get('validation_status', 'unknown')
                out.write(f'{sample_id}\\t{taxid}\\t{method}\\t{kraken_reads}\\t{hits}\\t{hit_rate:.4f}\\t{avg_identity:.2f}\\t{avg_coverage:.4f}\\t{status}\\n')

    print(f"Aggregated validation results: {total_samples} samples, {total_taxids} taxids", file=sys.stderr)
    print(f"  Confirmed: {confirmed}, Uncertain: {uncertain}, Rejected: {rejected}", file=sys.stderr)

    # Generate versions
    with open('versions.yml', 'w') as v:
        v.write(f'"AGGREGATE_VALIDATION_RESULTS":\\n')
        v.write(f'    python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    cat > validation_results.json << EOF
{
    "pipeline_version": "stub",
    "validation_method": "${validation_method}",
    "timestamp": "2025-01-01T00:00:00Z",
    "thresholds": {"hit_rate": 0.5, "identity": 90.0},
    "results": {},
    "summary": {
        "total_samples": 0,
        "total_taxids_validated": 0,
        "confirmed": 0,
        "uncertain": 0,
        "rejected": 0
    }
}
EOF

    echo -e "sample_id\\ttaxid\\tmethod\\tkraken_reads\\thits\\thit_rate\\tavg_identity\\tavg_coverage\\tstatus" > validation_summary.tsv

    cat <<-END_VERSIONS > versions.yml
    "AGGREGATE_VALIDATION_RESULTS":
    python: 3.11.0
END_VERSIONS
    """
}
