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
from typing import Any, List


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


def discover_files(outdir: str, category: str, extension: str) -> List[str]:
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


def main() -> None:
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
        "--assembly-files", default="",
        help="comma-separated canonical assembly stats filenames actually "
             "produced; empty means none were",
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
        "--produced-samples", default=None,
        help=("Comma-separated samples that actually emitted QC output. The "
              "difference from --samples is the set attempted but not "
              "produced, usually a QC failure absorbed by error isolation. "
              "Omitting the flag means 'not determined'; passing it empty "
              "means 'determined: none produced', which is not the same "
              "thing and must not be collapsed."),
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
    # None when the caller did not tell us: "not determined" must stay distinct
    # from "none failed", or this field becomes the false reassurance it exists
    # to prevent.
    #
    # The distinction is carried by the flag's PRESENCE, not by whether the
    # list is non-empty. Testing truthiness collapsed the two, so a batch in
    # which every sample failed QC -- an empty produced set, the single case
    # this field exists to report -- came out as null "not determined" instead
    # of naming the samples that failed.
    if args.produced_samples is None:
        produced = None
    else:
        produced = [s.strip() for s in args.produced_samples.split(",") if s.strip()]
    failed_samples = (
        sorted(set(samples) - set(produced)) if produced is not None else None
    )
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

    # Build expected file lists from samples and tool arguments.
    # File discovery is unreliable because MANIFEST_WRITER runs in its own
    # work directory, not the final publishDir. Instead, derive expected
    # filenames from the known samples and active tools.
    classification_files = (
        sorted(f"{s}.classification.json" for s in samples)
        if args.classifier else []
    )
    qc_files = (
        sorted(f"{s}.qc_stats.json" for s in samples)
        if args.qc_tool else []
    )
    # Validation filenames include taxid and cannot be predicted from samples
    # alone. Mark as available when validation is active; files can be
    # discovered by the frontend from the validation/ directory.
    validation_available = bool(args.validation_method)
    # Discovered, never derived. This used to build the filenames from the
    # sample list and the assembler flag, so a run whose every assembly task
    # failed still published a manifest asserting one stats file per sample --
    # files no consumer could open (nanometa_live assembly audit, 2026-09-03).
    # An empty --assembly-files with an assembler set is a real answer:
    # assembly ran and produced nothing.
    assembly_files = sorted(
        f for f in (args.assembly_files or "").split(",") if f.strip()
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
        # null means "not determined"; [] means "none failed".
        "failed_samples": (
            failed_samples if failed_samples is not None
            else existing.get("failed_samples")
        ),
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
                "available": validation_available,
                "files": [],
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
