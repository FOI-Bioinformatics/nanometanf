# foi-bioinformatics/nanometanf: Citations

## Pipeline Tools

### Core Analysis Tools

- **Dorado**: ONT basecalling and demultiplexing
  > Oxford Nanopore Technologies. (2023). Dorado. Retrieved from https://github.com/nanoporetech/dorado

- **Kraken2**: Taxonomic classification
  > Wood, D.E., Lu, J. & Langmead, B. Improved metagenomic analysis with Kraken 2. Genome Biol 20, 257 (2019). doi: [10.1186/s13059-019-1891-0](https://doi.org/10.1186/s13059-019-1891-0)

- **BLAST**: Sequence validation
  > Camacho, C., Coulouris, G., Avagyan, V., Ma, N., Papadopoulos, J., Bealer, K., & Madden, T.L. (2009). BLAST+: architecture and applications. BMC Bioinformatics 10, 421. doi: [10.1186/1471-2105-10-421](https://doi.org/10.1186/1471-2105-10-421)

### Quality Control

- **FastP**: Read quality control and filtering
  > Chen, S., Zhou, Y., Chen, Y., & Gu, J. (2018). fastp: an ultra-fast all-in-one FASTQ preprocessor. Bioinformatics, 34(17), i884-i890. doi: [10.1093/bioinformatics/bty560](https://doi.org/10.1093/bioinformatics/bty560)

- **FastQC**: Quality assessment
  > Andrews, S. (2010). FastQC: a quality control tool for high throughput sequence data. Available online at: http://www.bioinformatics.babraham.ac.uk/projects/fastqc

- **NanoPlot**: Nanopore-specific quality plots
  > De Coster, W., D'Hert, S., Schultz, D.T., Cruts, M., & Van Broeckhoven, C. (2018). NanoPack: visualizing and processing long-read sequencing data. Bioinformatics, 34(15), 2666-2669. doi: [10.1093/bioinformatics/bty149](https://doi.org/10.1093/bioinformatics/bty149)

- **MultiQC**: Report aggregation
  > Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics, 32(19), 3047-3048. doi: [10.1093/bioinformatics/btw354](https://doi.org/10.1093/bioinformatics/btw354)

### Assembly Tools

- **Flye**: Long-read genome assembly
  > Kolmogorov, M., Yuan, J., Lin, Y., & Pevzner, P.A. (2019). Assembly of long, error-prone reads using repeat graphs. Nature Biotechnology, 37(5), 540-546. doi: [10.1038/s41587-019-0072-8](https://doi.org/10.1038/s41587-019-0072-8)

- **Miniasm**: Lightweight assembly
  > Li, H. (2016). Miniasm: fast assembly for noisy long reads. Bioinformatics, 32(14), 2103-2110. doi: [10.1093/bioinformatics/btw152](https://doi.org/10.1093/bioinformatics/btw152)

- **Minimap2**: Read mapping
  > Li, H. (2018). Minimap2: pairwise alignment for nucleotide sequences. Bioinformatics, 34(18), 3094-3100. doi: [10.1093/bioinformatics/bty191](https://doi.org/10.1093/bioinformatics/bty191)

### Additional Tools

- **Filtlong**: Read length filtering
  > Wick, R. (2018). Filtlong. Retrieved from https://github.com/rrwick/Filtlong

- **Porechop**: Adapter trimming
  > Wick, R. (2018). Porechop. Retrieved from https://github.com/rrwick/Porechop

- **PycoQC**: Nanopore QC metrics
  > Leger, A., & Leonardi, T. (2019). pycoQC, interactive quality control for Oxford Nanopore Sequencing. Journal of Open Source Software, 4(34), 1236. doi: [10.21105/joss.01236](https://doi.org/10.21105/joss.01236)

- **Taxpasta**: Taxonomic profile standardization
  > Beber, M.E., Borry, M., Stamogiannos, A., & Pochon, Z. (2023). taxpasta: TAXonomic Profile Aggregation and STAndardisation. Journal of Open Source Software, 8(87), 5627. doi: [10.21105/joss.05627](https://doi.org/10.21105/joss.05627)

## Workflow Framework

- **Nextflow**: Workflow manager
  > Di Tommaso, P., Chatzou, M., Floden, E.W., Barja, P.P., Palumbo, E., & Notredame, C. (2017). Nextflow enables reproducible computational workflows. Nature Biotechnology, 35(4), 316-319. doi: [10.1038/nbt.3820](https://doi.org/10.1038/nbt.3820)

- **nf-core**: Community framework
  > Ewels, P.A., Peltzer, A., Fillinger, S., Patel, H., Alneberg, J., Wilm, A., Garcia, M.U., Di Tommaso, P., & Nahnsen, S. (2020). The nf-core framework for community-curated bioinformatics pipelines. Nature Biotechnology, 38(3), 276-278. doi: [10.1038/s41587-020-0439-x](https://doi.org/10.1038/s41587-020-0439-x)

## Software Dependencies

- **Conda**: Package management
  > Anaconda Software Distribution. (2020). Anaconda Documentation. Anaconda Inc. Retrieved from https://docs.anaconda.com/

- **Docker**: Containerization
  > Merkel, D. (2014). Docker: lightweight linux containers for consistent development and deployment. Linux Journal, 2014(239), 2.

- **Singularity/Apptainer**: HPC containerization
  > Kurtzer, G.M., Sochat, V., & Bauer, M.W. (2017). Singularity: Scientific containers for mobility of compute. PLoS ONE, 12(5), e0177459. doi: [10.1371/journal.pone.0177459](https://doi.org/10.1371/journal.pone.0177459)