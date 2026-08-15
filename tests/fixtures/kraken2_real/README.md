# Functional mini Kraken2 fixture (real classification)

Unlike `tests/fixtures/kraken2_db/` (byte-sized stub placeholders), this is a
**real, functional** Kraken2 database paired with reads it classifies, so tests
can assert genuine classification output (a non-empty report with classified
reads) rather than only that the pipeline did not crash.

## Layout

- `db/{hash,opts,taxo}.k2d` - a real Kraken2 database (~256 KB).
- `reads/barcode01/reads.fastq.gz` - reads the database classifies (a copy of
  `tests/fixtures/fastq/sample_minimal.fastq.gz`), arranged as a barcode
  subdirectory so it can be supplied via `--barcode_input_dir`.

Everything classifies to **taxid 562** (*Escherichia coli*, a real NCBI taxid
chosen so downstream taxid handling sees a plausible value). The reads are
synthetic, so the database is built *from the reads themselves* to make
classification deterministic and self-contained (no external genome or network).

## How it was built (reproducible)

```bash
DB=tests/fixtures/kraken2_real/db
mkdir -p "$DB/taxonomy"
# library: the test reads, every sequence assigned to taxid 562
gzip -dc tests/fixtures/fastq/sample_minimal.fastq.gz | \
  awk 'NR%4==1{h=substr($0,2); gsub(/[ \t].*/,"",h); print ">"h"|kraken:taxid|562"} NR%4==2{print}' \
  > "$DB/library.fa"
# minimal custom taxonomy: root(1) -> species(562)
printf '1\t|\t1\t|\tno rank\t|\n562\t|\t1\t|\tspecies\t|\n'                 > "$DB/taxonomy/nodes.dmp"
printf '1\t|\troot\t|\t|\tscientific name\t|\n562\t|\tEscherichia coli\t|\t|\tscientific name\t|\n' > "$DB/taxonomy/names.dmp"
kraken2-build --add-to-library "$DB/library.fa" --db "$DB" --no-masking
kraken2-build --build --db "$DB" --kmer-len 35 --minimizer-len 31 --minimizer-spaces 7
# keep only the runtime .k2d files; drop library.fa / taxonomy / library/ build dirs
```

Verify: `kraken2 --db db reads/barcode01/reads.fastq.gz --report -` reports
100 sequences classified at rank S, taxid 562.
