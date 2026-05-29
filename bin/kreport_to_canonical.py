#!/usr/bin/env python3
"""Convert kreport TSV to canonical classification JSON (Contract A).

Parses Kraken2/Centrifuge kreport format (6 tab-separated columns) and
produces a structured JSON with explicit taxonomy hierarchy via parent_taxid.
"""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple


def parse_kreport(filepath: str) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """Parse a kreport file and return taxa with hierarchy information.

    The kreport format uses leading whitespace on the taxon name to encode
    hierarchy depth. Each two spaces of indentation represents one level
    deeper in the taxonomy tree.
    """
    taxa = []
    # Stack tracks (taxid, indent_level) for hierarchy reconstruction
    parent_stack = []

    total_reads = 0
    classified_reads = 0
    unclassified_reads = 0

    with open(filepath, "r") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue

            parts = line.split("\t")
            if len(parts) < 6:
                continue

            percent = float(parts[0].strip())
            reads_clade = int(parts[1].strip())
            reads_direct = int(parts[2].strip())
            rank = parts[3].strip()
            taxid = int(parts[4].strip())
            raw_name = parts[5]

            # Compute indentation depth from leading spaces
            stripped_name = raw_name.lstrip(" ")
            indent = len(raw_name) - len(stripped_name)

            # Pop stack back to find parent at previous indent level
            while parent_stack and parent_stack[-1][1] >= indent:
                parent_stack.pop()

            parent_taxid = parent_stack[-1][0] if parent_stack else 0

            # Track unclassified vs classified
            if rank == "U":
                unclassified_reads = reads_clade
            elif taxid == 1 and rank == "R":
                # Root node: reads_clade is total classified
                classified_reads = reads_clade

            taxa.append({
                "taxid": taxid,
                "name": stripped_name,
                "rank": rank,
                "reads_clade": reads_clade,
                "reads_direct": reads_direct,
                "percent": percent,
                "parent_taxid": parent_taxid,
            })

            parent_stack.append((taxid, indent))

    # Total reads = classified + unclassified
    total_reads = classified_reads + unclassified_reads

    summary = {
        "total_reads": total_reads,
        "classified_reads": classified_reads,
        "unclassified_reads": unclassified_reads,
    }
    if total_reads > 0:
        summary["classification_rate"] = round(
            classified_reads / total_reads, 6
        )
    else:
        summary["classification_rate"] = 0.0

    return summary, taxa


def write_atomic(filepath: str, data: Any) -> None:
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


def build_sidecar(args: argparse.Namespace, source_file: str) -> Dict[str, Any]:
    """Build sidecar metadata JSON."""
    sidecar = {
        "contract_version": "1.0.0",
        "category": "classification",
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
        "is_cumulative": args.is_cumulative,
        "source_files": [source_file],
    }
    if args.batch_id is not None:
        sidecar["batch_id"] = args.batch_id
    return sidecar


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert kreport TSV to canonical classification JSON."
    )
    parser.add_argument(
        "--input", required=True, help="Input kreport file."
    )
    parser.add_argument(
        "--tool", required=True, help="Tool name (e.g., kraken2, centrifuge)."
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
    parser.add_argument(
        "--batch-id", type=int, default=None,
        help="Batch number (real-time mode)."
    )
    parser.add_argument(
        "--is-cumulative", action="store_true",
        help="Mark output as cumulative."
    )

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.stderr.write(
            "Error: input file not found: {}\n".format(args.input)
        )
        sys.exit(1)

    summary, taxa = parse_kreport(args.input)

    canonical = {
        "format_version": "1.0.0",
        "sample_id": args.sample,
        "summary": summary,
        "taxa": taxa,
    }

    sidecar = build_sidecar(args, os.path.basename(args.input))

    write_atomic(args.output, canonical)
    write_atomic(args.sidecar, sidecar)


if __name__ == "__main__":
    main()
