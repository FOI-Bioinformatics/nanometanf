#!/usr/bin/env python3
"""Convert Flye assembly_info.txt to canonical assembly JSON (Contract D).

Parses Flye's tab-separated assembly information file and optionally
computes GC content from a FASTA file.
"""

import argparse
import gzip
import json
import os
import sys
import tempfile
from datetime import datetime, timezone


def _open_fasta(fasta_path):
    """Open a FASTA file for text reading, transparently handling gzip.

    The FLYE module emits gzipped FASTA (*.assembly.fasta.gz); reading it
    as plain text fails with UnicodeDecodeError on the gzip magic byte.
    Sniff the magic rather than trusting the extension.
    """
    with open(fasta_path, "rb") as probe:
        magic = probe.read(2)
    if magic == b"\x1f\x8b":
        return gzip.open(fasta_path, "rt")
    return open(fasta_path, "r")


def compute_gc_from_fasta(fasta_path):
    """Compute GC content from a FASTA file (plain or gzipped).

    Returns GC fraction (0.0-1.0) across all sequences, or None if
    the file cannot be read or contains no sequence data.
    """
    gc_count = 0
    total_count = 0

    with _open_fasta(fasta_path) as f:
        for line in f:
            if line.startswith(">"):
                continue
            seq = line.strip().upper()
            for base in seq:
                if base in ("G", "C"):
                    gc_count += 1
                if base in ("A", "T", "G", "C"):
                    total_count += 1

    if total_count == 0:
        return None
    return round(gc_count / total_count, 6)


def compute_gc_per_contig(fasta_path):
    """Compute GC content per contig from a FASTA file (plain or gzipped).

    Returns a dictionary mapping contig name to GC fraction.
    """
    contigs = {}
    current_name = None
    gc_count = 0
    total_count = 0

    with _open_fasta(fasta_path) as f:
        for line in f:
            if line.startswith(">"):
                if current_name is not None and total_count > 0:
                    contigs[current_name] = round(gc_count / total_count, 6)
                current_name = line[1:].strip().split()[0]
                gc_count = 0
                total_count = 0
            else:
                seq = line.strip().upper()
                for base in seq:
                    if base in ("G", "C"):
                        gc_count += 1
                    if base in ("A", "T", "G", "C"):
                        total_count += 1

    if current_name is not None and total_count > 0:
        contigs[current_name] = round(gc_count / total_count, 6)

    return contigs


def compute_n50(lengths):
    """Compute N50 from a list of contig lengths."""
    if not lengths:
        return None
    sorted_lengths = sorted(lengths, reverse=True)
    total = sum(sorted_lengths)
    cumulative = 0
    for length in sorted_lengths:
        cumulative += length
        if cumulative >= total / 2.0:
            return length
    return None


def compute_l50(lengths):
    """Compute L50: the number of contigs whose lengths sum to >= 50% of total."""
    if not lengths:
        return None
    sorted_lengths = sorted(lengths, reverse=True)
    total = sum(sorted_lengths)
    cumulative = 0
    for i, length in enumerate(sorted_lengths, 1):
        cumulative += length
        if cumulative >= total / 2.0:
            return i
    return None


def parse_flye_assembly_info(filepath):
    """Parse Flye assembly_info.txt.

    Expected columns (tab-separated, with header):
      seq_name  length  cov.  circ.  repeat  mult.  alt_group  graph_path
    """
    contigs = []

    with open(filepath, "r") as f:
        header = f.readline()  # Skip header line
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue

            name = parts[0]
            length = int(parts[1])
            coverage = float(parts[2]) if len(parts) > 2 else 0.0
            is_circular = parts[3].strip().lower() in ("y", "yes", "+", "true")

            repeat_frac = 0.0
            if len(parts) > 4 and parts[4].strip().lower() not in ("", "n", "no"):
                try:
                    repeat_frac = float(parts[4])
                except ValueError:
                    # Some Flye versions use Y/N for repeat column
                    repeat_frac = 1.0 if parts[4].strip().lower() in (
                        "y", "yes"
                    ) else 0.0

            contig = {
                "name": name,
                "length": length,
                "coverage": coverage,
                "is_circular": is_circular,
            }
            if repeat_frac > 0:
                contig["repeat_fraction"] = repeat_frac

            contigs.append(contig)

    return contigs


def write_atomic(filepath, data):
    """Write JSON data atomically using a temporary file and rename."""
    dir_name = os.path.dirname(filepath) or "."
    os.makedirs(dir_name, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, filepath)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Convert Flye assembly_info.txt to canonical assembly JSON."
        )
    )
    parser.add_argument(
        "--input", required=True,
        help="Input assembly_info.txt file."
    )
    parser.add_argument(
        "--tool", required=True, help="Tool name (e.g., flye, miniasm)."
    )
    parser.add_argument(
        "--tool-version", required=True, help="Tool version string."
    )
    parser.add_argument(
        "--sample", required=True, help="Sample ID."
    )
    parser.add_argument(
        "--output", required=True, help="Output canonical JSON file."
    )
    parser.add_argument(
        "--sidecar", required=True, help="Output sidecar JSON file."
    )
    parser.add_argument(
        "--fasta", default=None,
        help="Optional FASTA file for GC content computation."
    )

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.stderr.write(
            "Error: input file not found: {}\n".format(args.input)
        )
        sys.exit(1)

    contigs = parse_flye_assembly_info(args.input)
    lengths = [c["length"] for c in contigs]

    # Compute per-contig GC if FASTA provided
    if args.fasta and os.path.isfile(args.fasta):
        gc_per_contig = compute_gc_per_contig(args.fasta)
        for contig in contigs:
            gc = gc_per_contig.get(contig["name"])
            if gc is not None:
                contig["gc_content"] = gc
        overall_gc = compute_gc_from_fasta(args.fasta)
    else:
        overall_gc = None

    summary = {
        "total_contigs": len(contigs),
        "total_length": sum(lengths),
    }

    if lengths:
        summary["largest_contig"] = max(lengths)
        n50 = compute_n50(lengths)
        if n50 is not None:
            summary["n50"] = n50
        l50 = compute_l50(lengths)
        if l50 is not None:
            summary["l50"] = l50

    circular_count = sum(1 for c in contigs if c.get("is_circular", False))
    summary["circular_contigs"] = circular_count

    if overall_gc is not None:
        summary["gc_content"] = overall_gc

    canonical = {
        "format_version": "1.0.0",
        "sample_id": args.sample,
        "summary": summary,
        "contigs": contigs,
    }

    sidecar = {
        "contract_version": "1.0.0",
        "category": "assembly_stats",
        "tool": {
            "name": args.tool,
            "version": args.tool_version,
        },
        "sample_id": args.sample,
        "timestamp": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "format_version": "1.0.0",
        "source_files": [os.path.basename(args.input)],
    }

    write_atomic(args.output, canonical)
    write_atomic(args.sidecar, sidecar)


if __name__ == "__main__":
    main()
