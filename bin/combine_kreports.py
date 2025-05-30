#!/usr/bin/env python3
# bin/combine_kreports.py
# Simplified version of KrakenTools combine_kreports.py

import argparse
import sys
from collections import defaultdict

def parse_kreport(filename):
    """Parse a Kraken report file"""
    data = defaultdict(lambda: {'count': 0, 'children': 0})

    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) < 6:
                continue

            percent = float(parts[0])
            count_tree = int(parts[1])
            count_direct = int(parts[2])
            level = parts[3]
            taxid = parts[4]
            name = parts[5]

            data[taxid] = {
                'percent': percent,
                'count_tree': count_tree,
                'count_direct': count_direct,
                'level': level,
                'name': name,
                'taxid': taxid
            }

    return data

def combine_reports(report_files):
    """Combine multiple Kraken reports"""
    all_taxa = set()
    all_data = []

    # Parse all reports
    for report_file in report_files:
        data = parse_kreport(report_file)
        all_data.append(data)
        all_taxa.update(data.keys())

    # Combine counts
    combined = defaultdict(lambda: {
        'count_tree': 0,
        'count_direct': 0,
        'level': '',
        'name': '',
        'taxid': ''
    })

    for taxid in all_taxa:
        for data in all_data:
            if taxid in data:
                combined[taxid]['count_tree'] += data[taxid]['count_tree']
                combined[taxid]['count_direct'] += data[taxid]['count_direct']
                combined[taxid]['level'] = data[taxid]['level']
                combined[taxid]['name'] = data[taxid]['name']
                combined[taxid]['taxid'] = taxid

    return combined

def calculate_percentages(combined_data):
    """Calculate percentages for combined data"""
    # Find root (taxid 1) for total count
    total = combined_data.get('1', {}).get('count_tree', 0)
    if total == 0:
        # If no root, sum all top-level counts
        total = sum(v['count_tree'] for v in combined_data.values() if v['level'] == 'R')

    if total == 0:
        total = 1  # Avoid division by zero

    for taxid, data in combined_data.items():
        data['percent'] = (data['count_tree'] / total) * 100

def write_kreport(combined_data, output_file, no_headers=False):
    """Write combined report in Kraken format"""
    # Sort by taxonomy hierarchy (simplified)
    sorted_taxa = sorted(combined_data.items(),
                        key=lambda x: (x[1]['level'], -x[1]['count_tree']))

    with open(output_file, 'w') as out:
        if not no_headers:
            out.write("# Combined Kraken Report\n")

        for taxid, data in sorted_taxa:
            # Calculate proper indentation based on level
            level_map = {'R': 0, 'D': 1, 'K': 2, 'P': 3, 'C': 4, 'O': 5, 'F': 6, 'G': 7, 'S': 8}
            indent = level_map.get(data['level'], 9) * 2

            out.write(f"{data['percent']:6.2f}\t")
            out.write(f"{data['count_tree']}\t")
            out.write(f"{data['count_direct']}\t")
            out.write(f"{data['level']}\t")
            out.write(f"{data['taxid']}\t")
            out.write(f"{' ' * indent}{data['name']}\n")

def main():
    parser = argparse.ArgumentParser(description='Combine multiple Kraken reports')
    parser.add_argument('-r', '--reports', nargs='+', required=True,
                       help='Input Kraken report files')
    parser.add_argument('-o', '--output', required=True,
                       help='Output combined report file')
    parser.add_argument('--no-headers', action='store_true',
                       help='Do not print header line')
    parser.add_argument('--only-combined', action='store_true',
                       help='Only output combined results (compatibility flag)')

    args = parser.parse_args()

    # Combine reports
    combined_data = combine_reports(args.reports)

    # Calculate percentages
    calculate_percentages(combined_data)

    # Write output
    write_kreport(combined_data, args.output, args.no_headers)

if __name__ == '__main__':
    main()
