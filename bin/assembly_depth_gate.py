#!/usr/bin/env python3
"""Decide whether a read set is deep enough to assemble, and record why.

Assembly is the one step that can run, succeed and publish a number that is
not a result. Measured on a real corpus (nanometa_live assembly audit,
2026-09-03): Flye published 63 contigs at an N50 of 12,368 built at a median
coverage of 4, and the run reported healthy. No target in that corpus reached
2x against its reference, where a usable draft needs roughly 30x.

So the useful question is not "did the assembler run" but "was there ever
enough sequence". This script answers it before the assembler is scheduled and
**always** writes a decision record, whether it says attempt or decline. A
declined assembly is a measurement with a stated reason; an absent assembly is
silence, and silence is what made a failure indistinguishable from a feature
that was switched off.

The decision is deliberately arithmetic and dependency-free: bases divided by
expected genome size. It is not a prediction of assembly quality, and it does
not try to be. It answers the one question that makes the assembler's output
interpretable.

Usage:
    assembly_depth_gate.py --reads in.fastq.gz --sample barcode05 \
        --scope targeted --taxid 263 --reference ref.fasta \
        --min-depth 30 --out barcode05.taxid263.assembly_decision.json
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import sys
from datetime import datetime, timezone

SCHEMA_VERSION = "1.0.0"

# A closed vocabulary: the GUI branches on `reason` and renders `reason_text`.
# Adding a value here is a contract change and belongs in docs/output.md.
REASONS = (
    "attempt",
    "insufficient_depth",
    "insufficient_bases",
    "no_reads",
    "no_reference",
    "low_depth_override",
)


def _open(path: str):
    return gzip.open(path, "rt") if str(path).endswith(".gz") else open(path)


def fastq_bases(paths) -> tuple:
    """(reads, bases) over one or more FASTQ files.

    Streams rather than loading: a pooled sample can be gigabytes. Counts the
    sequence line of each record, so a malformed tail is skipped rather than
    crashing the gate -- a gate that dies takes the decision record with it,
    which is the failure this whole mechanism exists to prevent.
    """
    reads = bases = 0
    for path in paths:
        if not path or not os.path.exists(path):
            continue
        try:
            with _open(path) as fh:
                for i, line in enumerate(fh):
                    if i % 4 == 1:
                        bases += len(line.strip())
                        reads += 1
        except OSError as exc:
            print(f"warning: could not read {path}: {exc}", file=sys.stderr)
    return reads, bases


def fasta_length(path: str):
    """Total bases of a FASTA, or None when absent or unreadable."""
    if not path or not os.path.exists(path):
        return None
    try:
        total = 0
        with _open(path) as fh:
            for line in fh:
                if not line.startswith(">"):
                    total += len(line.strip())
        return total or None
    except OSError:
        return None


def parse_size(text) -> int:
    """'5m' / '3.2g' / '4000000' as an integer of bases; 0 when unparseable."""
    if text is None:
        return 0
    s = str(text).strip().lower().replace(",", "")
    if not s:
        return 0
    mult = {"k": 1_000, "m": 1_000_000, "g": 1_000_000_000}.get(s[-1])
    try:
        return int(float(s[:-1]) * mult) if mult else int(float(s))
    except ValueError:
        return 0


def decide(reads, bases, genome_size, min_depth, min_bases, scope,
           allow_low_depth):
    """(decision, reason, depth) from the measurements alone. Pure."""
    depth = (bases / genome_size) if genome_size else None

    if reads == 0 or bases == 0:
        return "declined", "no_reads", depth

    if scope == "targeted":
        # A targeted assembly is of one organism, so depth against its
        # reference is the whole question.
        if not genome_size:
            return "declined", "no_reference", depth
        if depth is not None and depth < min_depth:
            if allow_low_depth:
                return "attempt", "low_depth_override", depth
            return "declined", "insufficient_depth", depth
        return "attempt", "attempt", depth

    # Whole-sample: there is no single genome to divide by, so the floor is a
    # total-yield one. A depth figure is still reported when a nominal genome
    # size is configured, but it does not gate.
    if bases < min_bases:
        if allow_low_depth:
            return "attempt", "low_depth_override", depth
        return "declined", "insufficient_bases", depth
    return "attempt", "attempt", depth


def reason_text(reason, reads, bases, genome_size, depth, min_depth,
                min_bases, scope, target):
    mb = bases / 1e6
    if reason == "no_reads":
        return f"No reads were available for {target}."
    if reason == "no_reference":
        return (f"No reference genome for {target}, so the depth needed to "
                "judge an assembly cannot be computed.")
    if reason == "insufficient_depth":
        short = max(0, int(min_depth * genome_size) - bases) / 1e6
        return (f"{mb:.2f} Mb assigned to {target}; {depth:.2f}x of a "
                f"{genome_size / 1e6:.2f} Mb reference. {min_depth:g}x is "
                f"needed for a usable draft, about {short:.0f} Mb more.")
    if reason == "insufficient_bases":
        return (f"{mb:.2f} Mb of reads for {target}; {min_bases / 1e6:.0f} Mb "
                "is the floor for a whole-sample assembly.")
    if reason == "low_depth_override":
        depth_part = f" ({depth:.2f}x)" if depth is not None else ""
        return (f"Assembling {target} at {mb:.2f} Mb{depth_part} because "
                "low-depth assembly was allowed. The contigs will be "
                "fragments, not a genome.")
    depth_part = f", {depth:.2f}x of the reference" if depth is not None else ""
    return f"{mb:.2f} Mb available for {target}{depth_part}."


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reads", nargs="*", default=[])
    ap.add_argument("--reference", default="")
    ap.add_argument("--sample", required=True)
    ap.add_argument("--taxid", default="")
    ap.add_argument("--scope", default="metagenome",
                    choices=["targeted", "metagenome"])
    ap.add_argument("--min-depth", type=float, default=30.0)
    ap.add_argument("--min-bases", type=float, default=100_000_000)
    ap.add_argument("--genome-size", default="",
                    help="nominal size when no reference is supplied")
    ap.add_argument("--allow-low-depth", action="store_true")
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    reads, bases = fastq_bases(args.reads)
    genome_size = fasta_length(args.reference) or parse_size(args.genome_size)
    genome_source = ("reference_fasta" if fasta_length(args.reference)
                     else ("genome_size_param" if genome_size else "none"))

    decision, reason, depth = decide(
        reads, bases, genome_size, args.min_depth, args.min_bases,
        args.scope, args.allow_low_depth)

    target = (f"taxid {args.taxid} in {args.sample}" if args.taxid
              else f"sample {args.sample}")
    record = {
        "schema_version": SCHEMA_VERSION,
        "sample_id": args.sample,
        "taxid": int(args.taxid) if str(args.taxid).isdigit() else None,
        "scope": args.scope,
        "attempt": args.attempt,
        "decision": decision,
        "reason": reason,
        "reason_text": reason_text(reason, reads, bases, genome_size, depth,
                                   args.min_depth, args.min_bases, args.scope,
                                   target),
        "reads": reads,
        "bases": bases,
        "expected_genome_size": genome_size or None,
        "genome_size_source": genome_source,
        "estimated_depth": round(depth, 4) if depth is not None else None,
        "required_depth": args.min_depth if args.scope == "targeted" else None,
        "required_bases": int(args.min_bases) if args.scope == "metagenome" else None,
        "low_depth_override": reason == "low_depth_override",
        "measured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    if decision == "declined" and genome_size:
        record["shortfall_bases"] = max(0, int(args.min_depth * genome_size) - bases)

    with open(args.out, "w") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")

    # stdout is the operator-visible line in the Nextflow log.
    print(f"{decision.upper()} {args.scope} {target}: {record['reason_text']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
