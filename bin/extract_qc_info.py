#!/usr/bin/env python3
# bin/extract_qc_info.py

import argparse
import gzip
import os
from datetime import datetime
from Bio import SeqIO

def get_file_creation_time(filepath):
    """Get file creation time"""
    stat = os.stat(filepath)
    return datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')

def process_fastq(filepath, sample_id):
    """Extract QC info from fastq file"""
    num_seqs = 0
    total_bp = 0

    open_func = gzip.open if filepath.endswith('.gz') else open

    with open_func(filepath, 'rt') as handle:
        for record in SeqIO.parse(handle, 'fastq'):
            num_seqs += 1
            total_bp += len(record.seq)

    return {
        'sample': sample_id,
        'file': os.path.basename(filepath),
        'timestamp': get_file_creation_time(filepath),
        'num_sequences': num_seqs,
        'total_bp': total_bp
    }

def main():
    parser = argparse.ArgumentParser(description='Extract QC information from FASTQ files')
    parser.add_argument('--input', nargs='+', required=True, help='Input FASTQ file(s)')
    parser.add_argument('--output', required=True, help='Output file')
    parser.add_argument('--sample', required=True, help='Sample ID')

    args = parser.parse_args()

    with open(args.output, 'w') as out:
        out.write('sample\tfile\ttimestamp\tnum_sequences\ttotal_bp\n')

        for input_file in args.input:
            qc_info = process_fastq(input_file, args.sample)
            out.write(f"{qc_info['sample']}\t{qc_info['file']}\t{qc_info['timestamp']}\t"
                     f"{qc_info['num_sequences']}\t{qc_info['total_bp']}\n")

if __name__ == '__main__':
    main()
