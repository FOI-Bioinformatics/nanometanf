#!/usr/bin/env python3
"""Convert FASTP JSON or SeqKit TSV to canonical QC JSON (Contract B).

Supports two input formats:
  - FASTP: nested JSON with summary.before_filtering / summary.after_filtering
  - SeqKit/Chopper: TSV with columns num_seqs, sum_len, min_len, avg_len,
    max_len, Q20(%), Q30(%), GC(%)
"""

import argparse
import csv
import json
import os
import sys
import tempfile
from datetime import datetime, timezone


def compute_n50(length_counts):
    """Compute N50 from a list of (length, count) tuples.

    Given a histogram of read lengths, N50 is the length at which 50% of
    total bases are in reads of that length or longer.
    """
    if not length_counts:
        return None

    total_bases = sum(length * count for length, count in length_counts)
    if total_bases == 0:
        return None

    half = total_bases / 2.0
    cumulative = 0
    # Sort by length descending
    for length, count in sorted(length_counts, reverse=True):
        cumulative += length * count
        if cumulative >= half:
            return length
    return None


def parse_fastp(filepath):
    """Parse FASTP JSON and extract QC statistics."""
    with open(filepath, "r") as f:
        data = json.load(f)

    result = {
        "before_filtering": None,
        "after_filtering": {},
        "filtering_result": None,
        "length_distribution": None,
    }

    # Before filtering
    bf = data.get("summary", {}).get("before_filtering", {})
    if bf:
        result["before_filtering"] = {
            "total_reads": bf.get("total_reads", 0),
            "total_bases": bf.get("total_bases", 0),
            "q20_rate": bf.get("q20_rate", 0.0),
            "q30_rate": bf.get("q30_rate", 0.0),
            "gc_content": bf.get("gc_content", 0.0),
            "mean_length": bf.get("mean_length", 0.0),
            "mean_quality": bf.get("quality_curves", {}).get(
                "mean_quality", 0.0
            ) if isinstance(bf.get("quality_curves"), dict) else 0.0,
        }

    # After filtering
    af = data.get("summary", {}).get("after_filtering", {})
    result["after_filtering"] = {
        "total_reads": af.get("total_reads", 0),
        "total_bases": af.get("total_bases", 0),
        "q20_rate": af.get("q20_rate", 0.0),
        "q30_rate": af.get("q30_rate", 0.0),
        "gc_content": af.get("gc_content", 0.0),
        "mean_length": af.get("mean_length", 0.0),
        "mean_quality": af.get("quality_curves", {}).get(
            "mean_quality", 0.0
        ) if isinstance(af.get("quality_curves"), dict) else 0.0,
    }

    # Filtering result
    fr = data.get("filtering_result", {})
    if fr:
        result["filtering_result"] = {
            "passed_filter_reads": fr.get("passed_filter_reads", 0),
            "low_quality_reads": fr.get("low_quality_reads", 0),
            "too_short_reads": fr.get("too_short_reads", 0),
            "too_long_reads": fr.get("too_long_reads", 0),
            "too_many_n_reads": fr.get("too_many_N_reads", 0),
            "adapter_trimmed_reads": fr.get("adapter_trimmed_reads", 0),
        }

    # Compute N50 from read length histogram if available
    rlh = data.get("read1_after_filtering", {}).get(
        "content_curves", {}
    )
    # FASTP stores length distribution under read_length_histogram key
    length_hist = data.get("insert_size", {}) or {}
    # Try the read1 before/after filtering length histograms
    for key in ["read1_after_filtering", "read1_before_filtering"]:
        section = data.get(key, {})
        if "total_cycles" in section:
            # total_cycles gives max read length observed
            pass

    # FASTP histogram: keys are length strings, values are counts
    hist_data = data.get("read_length_histogram", {})
    if not hist_data:
        # Try alternative location
        hist_data = {}

    if hist_data:
        length_counts = []
        for length_str, count in hist_data.items():
            try:
                length_counts.append((int(length_str), int(count)))
            except (ValueError, TypeError):
                continue
        n50 = compute_n50(length_counts)
        if n50 is not None:
            result["after_filtering"]["n50"] = n50
            if result["before_filtering"] is not None:
                result["before_filtering"]["n50"] = n50

    return result


def parse_seqkit(filepath):
    """Parse SeqKit TSV output and extract QC statistics.

    Expected columns: num_seqs, sum_len, min_len, avg_len, max_len,
    Q20(%), Q30(%), GC(%).
    """
    result = {
        "before_filtering": None,
        "after_filtering": {},
        "filtering_result": None,
        "length_distribution": None,
    }

    with open(filepath, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            # Use the first data row
            total_reads = int(row.get("num_seqs", "0").replace(",", ""))
            total_bases = int(row.get("sum_len", "0").replace(",", ""))
            avg_len = float(row.get("avg_len", "0").replace(",", ""))

            # SeqKit Q20/Q30 are percentages; convert to fractions
            q20_pct = row.get("Q20(%)", "0")
            q30_pct = row.get("Q30(%)", "0")
            gc_pct = row.get("GC(%)", "0")

            q20_rate = float(q20_pct) / 100.0 if q20_pct else 0.0
            q30_rate = float(q30_pct) / 100.0 if q30_pct else 0.0
            gc_content = float(gc_pct) / 100.0 if gc_pct else 0.0

            n50_val = row.get("N50", None)

            after = {
                "total_reads": total_reads,
                "total_bases": total_bases,
                "q20_rate": round(q20_rate, 6),
                "q30_rate": round(q30_rate, 6),
                "gc_content": round(gc_content, 6),
                "mean_length": avg_len,
            }

            if n50_val is not None and n50_val.strip():
                after["n50"] = int(n50_val.replace(",", ""))

            result["after_filtering"] = after
            break  # Only first row

    return result


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


def build_sidecar(args):
    """Build sidecar metadata JSON."""
    sidecar = {
        "contract_version": "1.0.0",
        "category": "qc_stats",
        "tool": {
            "name": args.tool,
            "version": args.tool_version,
        },
        "sample_id": args.sample,
        "timestamp": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "format_version": "1.0.0",
        "mode": args.mode,
        "source_files": [os.path.basename(args.input)],
    }
    return sidecar


def main():
    parser = argparse.ArgumentParser(
        description="Convert FASTP JSON or SeqKit TSV to canonical QC JSON."
    )
    parser.add_argument(
        "--input", required=True, help="Input file (FASTP JSON or SeqKit TSV)."
    )
    parser.add_argument(
        "--tool", required=True,
        help="Tool name (e.g., fastp, chopper, filtlong)."
    )
    parser.add_argument(
        "--tool-version", required=True, help="Tool version string."
    )
    parser.add_argument(
        "--sample", required=True, help="Sample ID."
    )
    parser.add_argument(
        "--mode", required=True, choices=["batch", "realtime"],
        help="Pipeline mode."
    )
    parser.add_argument(
        "--output", required=True, help="Output canonical JSON file."
    )
    parser.add_argument(
        "--sidecar", required=True, help="Output sidecar JSON file."
    )

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.stderr.write(
            "Error: input file not found: {}\n".format(args.input)
        )
        sys.exit(1)

    # Auto-detect format based on file extension and tool name
    tool_lower = args.tool.lower()
    if tool_lower == "fastp" or args.input.endswith(".json"):
        qc_data = parse_fastp(args.input)
    else:
        qc_data = parse_seqkit(args.input)

    canonical = {
        "format_version": "1.0.0",
        "sample_id": args.sample,
        "before_filtering": qc_data["before_filtering"],
        "after_filtering": qc_data["after_filtering"],
    }

    if qc_data.get("filtering_result") is not None:
        canonical["filtering_result"] = qc_data["filtering_result"]

    if qc_data.get("length_distribution") is not None:
        canonical["length_distribution"] = qc_data["length_distribution"]

    sidecar = build_sidecar(args)

    write_atomic(args.output, canonical)
    write_atomic(args.sidecar, sidecar)


if __name__ == "__main__":
    main()
