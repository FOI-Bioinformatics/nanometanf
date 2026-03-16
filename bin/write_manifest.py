#!/usr/bin/env python3
"""Write or update the canonical/_manifest.json file.

The manifest provides run-level metadata and eliminates glob-based tool
and sample detection in the frontend.
"""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone


def write_atomic(filepath, data):
    """Write JSON data atomically using a temporary file and rename."""
    dir_name = os.path.dirname(filepath) or "."
    os.makedirs(dir_name, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.rename(tmp_path, filepath)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def discover_files(outdir, category, extension):
    """Discover canonical output files for a given category.

    Scans the category subdirectory under outdir for files matching the
    expected naming pattern.
    """
    category_dir = os.path.join(outdir, category)
    if not os.path.isdir(category_dir):
        return []

    files = []
    for fname in sorted(os.listdir(category_dir)):
        if fname.endswith(extension) and not fname.endswith(".sidecar.json"):
            files.append(fname)
    return files


def main():
    parser = argparse.ArgumentParser(
        description="Write or update canonical/_manifest.json."
    )
    parser.add_argument(
        "--outdir", required=True,
        help="Canonical output directory (e.g., results/canonical)."
    )
    parser.add_argument(
        "--classifier", default="",
        help="Classifier tool name (e.g., kraken2)."
    )
    parser.add_argument(
        "--qc-tool", default="",
        help="QC tool name (e.g., fastp, chopper)."
    )
    parser.add_argument(
        "--assembler", default="",
        help="Assembler name (e.g., flye)."
    )
    parser.add_argument(
        "--validation-method", default="",
        help="Validation method (e.g., blast, minimap2, both)."
    )
    parser.add_argument(
        "--samples", default="",
        help="Comma-separated list of sample IDs."
    )
    parser.add_argument(
        "--mode", default="batch", choices=["batch", "realtime"],
        help="Pipeline mode."
    )

    args = parser.parse_args()

    samples = [s.strip() for s in args.samples.split(",") if s.strip()]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    manifest_path = os.path.join(args.outdir, "_manifest.json")

    # Load existing manifest if present (for updates)
    existing = {}
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, "r") as f:
                existing = json.load(f)
        except (json.JSONDecodeError, IOError):
            existing = {}

    # Discover available output files
    classification_files = discover_files(
        args.outdir, "classification", ".classification.json"
    )
    qc_files = discover_files(
        args.outdir, "qc", ".qc_stats.json"
    )
    validation_files = discover_files(
        args.outdir, "validation", ".json"
    )
    assembly_files = discover_files(
        args.outdir, "assembly", ".assembly_stats.json"
    )

    manifest = {
        "format_version": "1.0.0",
        "pipeline": existing.get("pipeline", {
            "name": "nanometanf",
            "version": "",
            "session_id": "",
        }),
        "mode": args.mode,
        "started_at": existing.get("started_at", now),
        "last_updated": now,
        "tools": {
            "classifier": args.classifier or existing.get(
                "tools", {}
            ).get("classifier", ""),
            "qc_tool": args.qc_tool or existing.get(
                "tools", {}
            ).get("qc_tool", ""),
            "assembler": args.assembler or existing.get(
                "tools", {}
            ).get("assembler", ""),
            "validation_method": args.validation_method or existing.get(
                "tools", {}
            ).get("validation_method", ""),
        },
        "samples": samples or existing.get("samples", []),
        "outputs": {
            "classification": {
                "available": len(classification_files) > 0,
                "files": classification_files,
            },
            "qc_stats": {
                "available": len(qc_files) > 0,
                "files": qc_files,
            },
            "validation": {
                "available": len(validation_files) > 0,
                "files": validation_files,
            },
            "assembly": {
                "available": len(assembly_files) > 0,
                "files": assembly_files,
            },
        },
    }

    write_atomic(manifest_path, manifest)


if __name__ == "__main__":
    main()
