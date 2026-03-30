# Getting Started with kailos-sarek (PGX Pipeline Testing)

## Prerequisites

Install the following on your machine:

| Tool | Install | Verify |
|------|---------|--------|
| **Nextflow** (≥25.x) | `curl -s https://get.nextflow.io \| bash` | `nextflow -version` |
| **Docker** | [docker.com/get-docker](https://docs.docker.com/get-docker/) | `docker --version` |
| **samtools** | `brew install samtools` (macOS) | `samtools --version` |
| **bcftools** | `brew install bcftools` (macOS) | `bcftools --version` |

## Clone the Repository

```bash
git clone <repo-url> kailos-sarek
cd kailos-sarek
```

## Step 1 — Create conf/local.config

This file caps per-process resource usage to fit your machine. Create it at the repo root:

```groovy
process {
    resourceLimits = [
        cpus: 4,
        memory: '16.GB',
        time: '4.h'
    ]
}
```

Adjust `cpus` to match your machine (`sysctl -n hw.ncpu` to check). This file is gitignored and must be created locally.

## Step 2 — Verify Setup with the Built-in Test

```bash
nextflow run . -profile test,docker --outdir results_test
```

Expected: completes in ~3 minutes with `Pipeline completed successfully`.

## Step 3 — Full Pipeline from FASTQs (with UMI support)

### Samplesheet

Create a CSV with one row per lane:

```csv
patient,sex,status,sample,lane,fastq_1,fastq_2
PATIENT_ID,XX,0,SAMPLE_ID,L001,/path/to/SAMPLE_L001_R1_001.fastq.gz,/path/to/SAMPLE_L001_R2_001.fastq.gz
PATIENT_ID,XX,0,SAMPLE_ID,L002,/path/to/SAMPLE_L002_R1_001.fastq.gz,/path/to/SAMPLE_L002_R2_001.fastq.gz
PATIENT_ID,XX,0,SAMPLE_ID,L003,/path/to/SAMPLE_L003_R1_001.fastq.gz,/path/to/SAMPLE_L003_R2_001.fastq.gz
PATIENT_ID,XX,0,SAMPLE_ID,L004,/path/to/SAMPLE_L004_R1_001.fastq.gz,/path/to/SAMPLE_L004_R2_001.fastq.gz
```

### Run command (panel-targeted)

```bash
nextflow run . -profile docker \
  -c conf/local.config \
  --input tests/csv/3.0/my_fastq_sample.csv \
  --aligner bwa-mem \
  --umi_read_structure '+T +T' \
  --umi_in_read_header \
  --tools haplotypecaller \
  --skip_tools haplotypecaller_filter \
  --igenomes_ignore \
  --fasta /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa \
  --fasta_fai /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai \
  --dict /kdata/reference_genomes/hg19/hg19_samtools/hg19.dict \
  --bwa /kdata/reference_genomes/hg19/hg19_samtools/ \
  --dbsnp /kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz \
  --known_indels /kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz \
  --intervals tests/csv/3.0/PGX.5.7.1.targets.bed \
  --outdir results_my_sample
```

To run whole-genome (no panel restriction), replace `--intervals ...` with `--no_intervals`.

**Pipeline steps executed:**
FASTQC → Fgbio FastqToBam → BAM2FASTQ → BWA-MEM (ALIGN_UMI, with `samtools fixmate`) → MERGE_CONSENSUS → GroupReadsByUmi → CallMolecularConsensusReads → FASTP → BWA-MEM (second alignment) → MarkDuplicates → BQSR → HaplotypeCaller → VCF QC → MultiQC

### Why `--aligner bwa-mem` (not `bwa-mem2`)

Building a BWA-MEM2 index for hg19 requires ~32 GB RAM inside the Docker VM — at the limit of what a 36 GB machine can provide. Using BWA v1 (`bwa-mem`) avoids this since the index already exists at `/kdata/reference_genomes/hg19/hg19_samtools/`. Results are functionally equivalent for germline calling.

### Why `--igenomes_ignore`

Without this flag, sarek defaults to `genome = 'GATK.GRCh38'` which overrides `--bwa`, `--dbsnp`, and `--known_indels` with hg38 S3 paths. This causes a contig mismatch at BQSR (hg38 reads vs hg19 reference). `--igenomes_ignore` disables the iGenomes defaults so all reference paths are taken explicitly from the command line.

## Panel BED File

The PGX panel intervals file is at `tests/csv/3.0/PGX.5.7.1.targets.bed` (134 amplicon regions, hg19 `chr`-prefixed coordinates, derived from `PGX.5.7.1.bed` FO entries).

To regenerate it from a new design BED:

```bash
grep -v "^browser\|^track" /path/to/PGX.design.bed \
  | awk '$4 ~ /-FO\./' \
  | cut -f1-3 \
  | sort -k1,1V -k2,2n \
  | uniq \
  > tests/csv/3.0/PGX.5.7.1.targets.bed
```

## Demo Walkthrough

For a live demonstration using the existing test sample (tr_106960, 4-lane FASTQs):

**Step 1 — Download the demo FASTQs**

```bash
cd ~/ktmp
aws s3 cp --recursive s3://kailos-blue-seq-results-clia/2271/sr_2271_PartialComputes_Bcl2FastqDemux_Samples_1730378094_707048/Unaligned/P-3130-31/K260/ .
```

**Step 2 — Run the pipeline**

The samplesheet (`demo/samplesheet.csv`) and panel BED (`demo/PGX.5.7.1.targets.bed`) are already in the repo. From the repo root:

```bash
nextflow run . -profile docker \
  -c conf/local.config \
  --input demo/samplesheet.csv \
  --aligner bwa-mem \
  --umi_read_structure '+T +T' \
  --umi_in_read_header \
  --tools haplotypecaller \
  --skip_tools haplotypecaller_filter \
  --igenomes_ignore \
  --fasta /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa \
  --fasta_fai /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai \
  --dict /kdata/reference_genomes/hg19/hg19_samtools/hg19.dict \
  --bwa /kdata/reference_genomes/hg19/hg19_samtools/ \
  --dbsnp /kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz \
  --known_indels /kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz \
  --intervals demo/PGX.5.7.1.targets.bed \
  --outdir results_demo
```

Completes in ~17 minutes. To replay instantly from cache (useful for demos):

```bash
nextflow run . -profile docker \
  -c conf/local.config \
  --input demo/samplesheet.csv \
  --aligner bwa-mem \
  --umi_read_structure '+T +T' \
  --umi_in_read_header \
  --tools haplotypecaller \
  --skip_tools haplotypecaller_filter \
  --igenomes_ignore \
  --fasta /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa \
  --fasta_fai /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai \
  --dict /kdata/reference_genomes/hg19/hg19_samtools/hg19.dict \
  --bwa /kdata/reference_genomes/hg19/hg19_samtools/ \
  --dbsnp /kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz \
  --known_indels /kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz \
  --intervals demo/PGX.5.7.1.targets.bed \
  --outdir results_demo \
  -resume
```

**Step 3 — Compare against Kailos production VCF**

```bash
./scripts/compare_vcf.sh \
  results_demo/variant_calling/haplotypecaller/LKG-240292_S1/LKG-240292_S1.haplotypecaller.vcf.gz \
  /path/to/kailos_filtered.vcf.gz \
  demo/PGX.5.7.1.targets.bed
```

## Reference Data

| File | Path |
|------|------|
| hg19 FASTA | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.fa` |
| FASTA index | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai` |
| Sequence dict | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.dict` |
| BWA v1 index | `/kdata/reference_genomes/hg19/hg19_samtools/` (`.amb`, `.ann`, `.bwt`, `.pac`, `.sa`) |
| dbSNP 132 | `/kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz` |
| Mills indels | `/kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz` |
| PGX panel BED | `tests/csv/3.0/PGX.5.7.1.targets.bed` |

## Custom Code Changes:

These modifications to the upstream nf-core/sarek source are required for the Kailos PGX use case:

### 1. `modules/nf-core/bwa/mem/main.nf`
Added `ext.postprocess` support to allow injecting a `samtools fixmate` step into the BWA alignment pipe. This adds mate score tags (`ms`) needed for downstream duplicate-aware processing.

### 2. `conf/modules/umi.config`
Configures the `ext.postprocess` for the ALIGN_UMI step:
```groovy
ext.postprocess = '| samtools fixmate -m -u - -'
```

### 3. `subworkflows/local/fastq_create_umi_consensus_fgbio/main.nf`
Fixed a bug introduced in sarek PR #2124 (lane-variantcalling): the `sample_lane_id` meta field (lane-specific) was included in the `groupKey` map, preventing multi-lane samples from merging in `MERGE_CONSENSUS`. Fixed by excluding `sample_lane_id` before creating the groupKey.

### 4. `subworkflows/local/fastq_preprocess_gatk/main.nf`
Fixed `FGBIO_COPYUMIFROMREADNAME` being called after UMI consensus re-alignment when `--umi_read_structure` is set. At that stage, FastqToBam has already extracted UMIs from read names into the `RX` tag, leaving no UMI sequence in the read name. Fixed by adding `&& !params.umi_read_structure` to the condition.

## What Sarek Covers vs. the Full PGX Pipeline

| PGX Block | Sarek Coverage |
|-----------|---------------|
| 1. BCL Demux | Not supported — provide FASTQs |
| 2. Trimming | fastp (replaces Trimmomatic) |
| 3. Alignment (BWA) | Supported (`bwa-mem`) |
| 4. Read Scrubbing (KGtools) | Not in sarek — custom module needed |
| 5. UMI Consensus (Fgbio) | Supported |
| 6. Variant Calling (GATK HC) | Supported |
| 7. Pileup (samtools mpileup) | Not in this workflow — custom module needed |
| 8–13. Genotyping, QC, Reports | Not in sarek — custom modules needed |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `incompatible contigs` at BQSR | Add `--igenomes_ignore` and supply all hg19 reference paths explicitly |
| `BWAMEM2_INDEX` OOM killed (exit 137) | Use `--aligner bwa-mem` — BWA-MEM2 index building requires ~32 GB Docker memory; the hg19 BWA v1 index already exists and avoids this entirely |
| `No valid UMI found in read name` | Add `&& !params.umi_read_structure` fix to `fastq_preprocess_gatk/main.nf` (custom fix #4 above) |
| Multi-lane sample stalls after ALIGN_UMI | Apply `sample_lane_id` groupTuple fix to `fastq_create_umi_consensus_fgbio/main.nf` (custom fix #3 above) |
| `Cannot extract flowcell ID` warning | Safe to ignore — test data has non-standard FASTQ headers |
