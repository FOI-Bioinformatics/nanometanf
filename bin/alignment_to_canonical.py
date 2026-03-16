#!/usr/bin/env python3
"""Convert PAF or BLAST outfmt-6 to canonical alignment TSV (Contract C).

Produces a tab-separated file with named columns, replacing positional
index access used in the current frontend parsers.
"""

import argparse
import os
import sys


# Canonical TSV header
HEADER = [
    "query_id", "ref_name", "ref_length", "ref_start", "ref_end",
    "identity", "mapq", "alignment_length", "evalue", "bitscore",
    "query_length", "query_coverage",
]


def parse_blast(filepath):
    """Parse BLAST outfmt-6 with extended columns.

    Expected BLAST format (15 columns):
      qseqid sseqid pident length mismatch gapopen qstart qend
      sstart send evalue bitscore qlen slen qcovs
    """
    rows = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 12:
                continue

            query_id = parts[0]
            ref_name = parts[1]
            identity = float(parts[2])
            alignment_length = int(parts[3])
            # parts[4] = mismatch, parts[5] = gapopen
            # parts[6] = qstart, parts[7] = qend
            ref_start = int(parts[8])
            ref_end = int(parts[9])
            evalue = float(parts[10])
            bitscore = float(parts[11])

            # Extended columns (may not be present)
            query_length = int(parts[12]) if len(parts) > 12 else -1
            ref_length = int(parts[13]) if len(parts) > 13 else -1
            query_coverage = float(parts[14]) if len(parts) > 14 else -1.0

            rows.append([
                query_id, ref_name, str(ref_length), str(ref_start),
                str(ref_end), "{:.2f}".format(identity), "255",
                str(alignment_length), "{:.2e}".format(evalue),
                "{:.1f}".format(bitscore), str(query_length),
                "{:.1f}".format(query_coverage),
            ])

    return rows


def parse_paf(filepath):
    """Parse minimap2 PAF output.

    PAF columns (0-indexed):
      0: qname, 1: qlen, 2: qstart, 3: qend, 4: strand,
      5: tname, 6: tlen, 7: tstart, 8: tend, 9: matches,
      10: block_len, 11: mapq
    """
    rows = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 12:
                continue

            query_id = parts[0]
            query_length = int(parts[1])
            q_start = int(parts[2])
            q_end = int(parts[3])
            ref_name = parts[5]
            ref_length = int(parts[6])
            ref_start = int(parts[7])
            ref_end = int(parts[8])
            matches = int(parts[9])
            block_len = int(parts[10])
            mapq = int(parts[11])

            # Compute identity from matches / block_len
            identity = (
                (matches / block_len * 100.0) if block_len > 0 else 0.0
            )

            # Compute query coverage
            q_aligned = q_end - q_start
            query_coverage = (
                (q_aligned / query_length * 100.0)
                if query_length > 0 else 0.0
            )

            rows.append([
                query_id, ref_name, str(ref_length), str(ref_start),
                str(ref_end), "{:.2f}".format(identity), str(mapq),
                str(block_len), "-1", "-1", str(query_length),
                "{:.1f}".format(query_coverage),
            ])

    return rows


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Convert PAF or BLAST outfmt-6 to canonical alignment TSV."
        )
    )
    parser.add_argument(
        "--input", required=True,
        help="Input alignment file (PAF or BLAST outfmt-6)."
    )
    parser.add_argument(
        "--tool", required=True,
        help="Tool name (e.g., minimap2, blast)."
    )
    parser.add_argument(
        "--format", required=True, choices=["paf", "blast"],
        dest="fmt", help="Input file format."
    )
    parser.add_argument(
        "--sample", required=True, help="Sample ID."
    )
    parser.add_argument(
        "--taxid", required=True, help="Taxonomy ID."
    )
    parser.add_argument(
        "--output", required=True, help="Output canonical TSV file."
    )

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        sys.stderr.write(
            "Error: input file not found: {}\n".format(args.input)
        )
        sys.exit(1)

    if args.fmt == "blast":
        rows = parse_blast(args.input)
    else:
        rows = parse_paf(args.input)

    with open(args.output, "w") as f:
        f.write("\t".join(HEADER) + "\n")
        for row in rows:
            f.write("\t".join(row) + "\n")


if __name__ == "__main__":
    main()
