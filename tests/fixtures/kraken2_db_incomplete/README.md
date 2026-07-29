A deliberately incomplete Kraken2 database: hash.k2d and opts.k2d are
present, taxo.k2d is missing.

Used by tests/failure_paths.nf.test to assert the pipeline refuses a
partial database and names the missing file, rather than starting a run
that dies later inside the kraken2 binary with an error the operator
cannot map back to the cause.

Mirrors a real field scenario: a database copied onto a USB drive that
ran out of space, or an interrupted transfer.
