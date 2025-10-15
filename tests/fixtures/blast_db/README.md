# BLAST Database Test Fixture

## Contents

This directory contains a minimal BLAST nucleotide database for testing the validation subworkflow.

### Files

- `test_sequences.fasta` - Source FASTA file with 5 test sequences
- `test_db.*` - BLAST database files created with makeblastdb

### Test Sequences

The database contains 5 bacterial test sequences:
1. Escherichia coli (240 bp)
2. Salmonella enterica (240 bp)
3. Pseudomonas aeruginosa (240 bp)
4. Bacillus subtilis (240 bp)
5. Staphylococcus aureus (240 bp)

### Recreation

If the database needs to be recreated:

```bash
cd tests/fixtures/blast_db
makeblastdb -in test_sequences.fasta -dbtype nucl -out test_db
```

### Usage in Tests

Tests should reference the database as:
```groovy
db = file("${projectDir}/tests/fixtures/blast_db/test_db")
```

### Size

Total size: ~172 KB (suitable for version control)

### Created

2025-10-15 - nanometanf v1.1.0 test infrastructure improvements
