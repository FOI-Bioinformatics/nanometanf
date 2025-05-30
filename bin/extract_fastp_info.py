#!/usr/bin/env python3
# bin/extract_fastp_info.py

import argparse
import json

def main():
    parser = argparse.ArgumentParser(description='Extract info from fastp JSON report')
    parser.add_argument('--input', required=True, help='Input fastp JSON file')
    parser.add_argument('--output', required=True, help='Output file')

    args = parser.parse_args()

    with open(args.input, 'r') as f:
        data = json.load(f)

    summary = data.get('summary', {})
    before = summary.get('before_filtering', {})
    after = summary.get('after_filtering', {})

    with open(args.output, 'w') as out:
        out.write('file\ttotal_reads_before\ttotal_bases_before\tq20_rate_before\tq30_rate_before\t')
        out.write('total_reads_after\ttotal_bases_after\tq20_rate_after\tq30_rate_after\t')
        out.write('reads_filtered\tpercent_filtered\n')

        reads_filtered = before.get('total_reads', 0) - after.get('total_reads', 0)
        percent_filtered = (reads_filtered / before.get('total_reads', 1)) * 100 if before.get('total_reads', 0) > 0 else 0

        out.write(f"{args.input}\t")
        out.write(f"{before.get('total_reads', 0)}\t{before.get('total_bases', 0)}\t")
        out.write(f"{before.get('q20_rate', 0)}\t{before.get('q30_rate', 0)}\t")
        out.write(f"{after.get('total_reads', 0)}\t{after.get('total_bases', 0)}\t")
        out.write(f"{after.get('q20_rate', 0)}\t{after.get('q30_rate', 0)}\t")
        out.write(f"{reads_filtered}\t{percent_filtered:.2f}\n")

if __name__ == '__main__':
    main()
