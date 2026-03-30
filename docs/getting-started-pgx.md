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

### Run Command Parameter Reference

| Parameter | What it does |
|-----------|-------------|
| `nextflow run .` | Run the pipeline from the current directory (uses `main.nf`) |
| `-profile docker` | Use Docker containers for all processes (as opposed to Conda or Singularity) |
| `-c conf/local.config` | Load the local resource limits config — caps CPUs/memory/time to fit your machine |
| `-resume` | Resume from Nextflow's cache; skips any processes whose inputs haven't changed |
| `--input` | Path to the samplesheet CSV listing patients, samples, lanes, and FASTQ paths |
| `--aligner bwa-mem` | Use BWA v1 for alignment (not BWA-MEM2) — the hg19 v1 index already exists; MEM2 requires ~32 GB to build |
| `--umi_read_structure '+T +T'` | Tells Fgbio the UMI is embedded in the read name (one UMI per read pair, template bases only — no fixed bases) |
| `--umi_in_read_header` | UMIs are in the FASTQ read name field, not a separate read (R3) file |
| `--tools haplotypecaller` | Run GATK HaplotypeCaller for germline variant calling |
| `--skip_tools haplotypecaller_filter` | Skip the VQSR/hard-filter post-processing step — output raw HC calls for comparison |
| `--igenomes_ignore` | Disable iGenomes defaults (which would override reference paths with GRCh38 S3 URLs and cause a contig mismatch against hg19) |
| `--fasta` | Path to the hg19 reference genome FASTA |
| `--fasta_fai` | Path to the FASTA index (`.fai`) — required by tools that do random access into the reference |
| `--dict` | Path to the sequence dictionary (`.dict`) — required by GATK tools |
| `--bwa` | Directory containing the BWA v1 index files (`.amb`, `.ann`, `.bwt`, `.pac`, `.sa`) |
| `--dbsnp` | dbSNP VCF used by BQSR (Base Quality Score Recalibration) to identify known variant sites |
| `--known_indels` | Mills & 1000G gold-standard indel VCF used by BQSR for known indel sites |
| `--intervals` | BED file restricting variant calling to panel target regions — omit or use `--no_intervals` for WGS |
| `--outdir` | Directory where all pipeline outputs are written |

**Pipeline steps executed:**
FASTQC → Fgbio FastqToBam → BAM2FASTQ → BWA-MEM (ALIGN_UMI, with `samtools fixmate`) → MERGE_CONSENSUS → GroupReadsByUmi → CallMolecularConsensusReads → FASTP → BWA-MEM (second alignment) → MarkDuplicates → BQSR → HaplotypeCaller → VCF QC → MultiQC

### Why `--aligner bwa-mem` (not `bwa-mem2`)

Building a BWA-MEM2 index for hg19 requires ~32 GB RAM inside the Docker VM — at the limit of what a 36 GB machine can provide. Using BWA v1 (`bwa-mem`) avoids this since the index already exists at `/kdata/reference_genomes/hg19/hg19_samtools/`. Results are functionally equivalent for germline calling.

### Why `--igenomes_ignore`

Without this flag, sarek defaults to `genome = 'GATK.GRCh38'` which overrides `--bwa`, `--dbsnp`, and `--known_indels` with hg38 S3 paths. This causes a contig mismatch at BQSR (hg38 reads vs hg19 reference). `--igenomes_ignore` disables the iGenomes defaults so all reference paths are taken explicitly from the command line.

## Panel BED File

The PGX panel intervals file is at `demo/PGX.5.2.1.targets.bed` (1,241 SNP target loci, hg19 `chr`-prefixed coordinates, derived from the `PGX.5.2.1_genetic_test_targets.bed` design file on S3).

To regenerate it from the design BED:

```bash
grep -v "^track\|^browser" /path/to/PGX.5.2.1_genetic_test_targets.bed \
  | cut -f1-3 \
  | sort -k1,1V -k2,2n \
  > demo/PGX.5.2.1.targets.bed
```

> **Note:** PGX 5.2.1 is a SNP-loci panel (1-bp positions with rs IDs). There are no amplicon FO entries — all entries are already the target positions, so no `awk` filtering is needed.

## Demo Walkthrough

For a live demonstration using the existing test sample (tr_106960, 4-lane FASTQs):

**Step 1 — Download the demo FASTQs**

```bash
cd ~/ktmp
aws s3 cp --recursive s3://kailos-blue-seq-results-clia/2271/sr_2271_PartialComputes_Bcl2FastqDemux_Samples_1730378094_707048/Unaligned/P-3130-31/K260/ .
```

**Step 2 — Run the pipeline**

The samplesheet (`demo/samplesheet.csv`) and panel BED (`demo/PGX.5.2.1.targets.bed`) are already in the repo. From the repo root (~/kailos-sarek):

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
  --intervals demo/PGX.5.2.1.targets.bed \
  --outdir results_demo
```

Completes in ~11 minutes. To replay instantly from cache (useful for demos):

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
  --intervals demo/PGX.5.2.1.targets.bed \
  --outdir results_demo \
  -resume
```

**Step 3 — Compare against Kailos production VCF**

Place the Kailos filtered VCF in `demo/` and compress/index it if needed:

```bash
bgzip demo/tr_106960.kailos_filtered.vcf
bcftools index demo/tr_106960.kailos_filtered.vcf.gz
```

Then run the comparison restricted to the panel BED:

```bash
./scripts/compare_vcf.sh \
  results_demo/variant_calling/haplotypecaller/LKG-240292_S1/LKG-240292_S1.haplotypecaller.vcf.gz \
  demo/tr_106960.kailos_filtered.vcf.gz \
  demo/PGX.5.2.1.targets.bed
```

## Apples-to-Apples Comparison (Starting from Scrubbed BAM)

The full pipeline run above starts from FASTQs and includes UMI consensus and re-alignment, while the Kailos production pipeline applies a read-scrubbing step (KGtools) before variant calling. To isolate just the BQSR + HaplotypeCaller difference — removing the scrubbing variable — start sarek from the Kailos scrubbed BAM directly.

**Step 1 — Create the BAM samplesheet**

The samplesheet is already at `demo/samplesheet_scrubbed_bam.csv`. It points to `/ktmp/tr_106960.scrubbed.bam`.

**Step 2 — Run from scrubbed BAM**

```bash
nextflow run . -profile docker \
  -c conf/local.config \
  --input demo/samplesheet_scrubbed_bam.csv \
  --step prepare_recalibration \
  --tools haplotypecaller \
  --skip_tools haplotypecaller_filter \
  --igenomes_ignore \
  --fasta /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa \
  --fasta_fai /kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai \
  --dict /kdata/reference_genomes/hg19/hg19_samtools/hg19.dict \
  --dbsnp /kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz \
  --known_indels /kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz \
  --intervals demo/PGX.5.2.1.targets.bed \
  --outdir results_scrubbed_bam
```

Note: `--aligner` and `--bwa` are not needed here since alignment is skipped. `--step prepare_recalibration` tells sarek to start from the BAM and run BQSR → HaplotypeCaller.

**Step 3 — Compare**

```bash
./scripts/compare_vcf.sh \
  results_scrubbed_bam/variant_calling/haplotypecaller/LKG-240292_S1/LKG-240292_S1.haplotypecaller.vcf.gz \
  demo/tr_106960.kailos_filtered.vcf.gz \
  demo/PGX.5.2.1.targets.bed
```

Any remaining discordance here is purely BQSR parameters or HaplotypeCaller settings — not alignment or scrubbing differences.

## Reference Data

| File | Path |
|------|------|
| hg19 FASTA | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.fa` |
| FASTA index | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.fa.fai` |
| Sequence dict | `/kdata/reference_genomes/hg19/hg19_samtools/hg19.dict` |
| BWA v1 index | `/kdata/reference_genomes/hg19/hg19_samtools/` (`.amb`, `.ann`, `.bwt`, `.pac`, `.sa`) |
| dbSNP 132 | `/kdata/reference_genomes/hg19/dbsnp_132/dbsnp_132.hg19.vcf.gz` |
| Mills indels | `/kdata/reference_genomes/hg19/hg19_mills/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.gz` |
| PGX panel BED | `demo/PGX.5.2.1.targets.bed` |

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

## Kailos Production Pipeline vs. Sarek — Side-by-Side

| Step | Kailos Production | Sarek Run (results_demo) |
|---|---|---|
| BCL Demux | Internal demux tool | — (started from FASTQs) |
| FASTQ QC | FastQC | FASTQC (x4 lanes) |
| UMI Extraction | KGtools / read header parsing | Fgbio FASTQTOBAM (x4 lanes) |
| Alignment (initial) | BWA-MEM | BWAMEM1_MEM (x4 lanes, via ALIGN_UMI) |
| BAM → FASTQ conversion | — | BAM2FASTQ (x4 lanes) |
| Lane Merge | samtools merge | MERGE_CONSENSUS |
| UMI Grouping | KGtools | Fgbio GROUPREADSBYUMI |
| UMI Consensus | KGtools | Fgbio CALLUMICONSENSUS |
| Consensus BAM → FASTQ | — | CONVERT_FASTQ_UMI (collate + view + merge) |
| Adapter Trimming | Trimmomatic | FASTP |
| Re-alignment | BWA-MEM | BWAMEM1_MEM (x4 intervals) |
| **Read Scrubbing** | **KGtools kailos-scrubber** | **— NOT RUN** |
| Duplicate Marking | GATK MarkDuplicates | GATK4_MARKDUPLICATES |
| Coverage QC (post-markdup) | — | MOSDEPTH + SAMTOOLS_STATS |
| Base Quality Recalibration | GATK BQSR | GATK4_BASERECALIBRATOR → GATK4_APPLYBQSR |
| Coverage QC (post-recal) | — | MOSDEPTH + SAMTOOLS_STATS |
| Variant Calling | GATK HaplotypeCaller | GATK4_HAPLOTYPECALLER |
| VCF QC | — | BCFTOOLS_STATS + VCFTOOLS |
| Variant Filtering | Kailos custom filter | — NOT RUN |
| Pileup / MQ0 BAM | samtools mpileup | — NOT RUN |
| UMI Allele Stats | KGtools | — NOT RUN |
| Genotyping / Clinical Reports | Internal tools | — NOT RUN |
| QC Reporting | Internal reports | MULTIQC |

## VCF Comparison Results (tr_106960 / LKG-240292_S1)

| Comparison | Shared | Sarek-only | Kailos-only | Recall | Precision |
|---|---|---|---|---|---|
| FASTQ vs Kailos GATK raw | 29 | 0 | 25 | 53.7% | 100% |
| FASTQ vs Kailos filtered | 29 | 0 | 25 | 53.7% | 100% |
| Scrubbed BAM vs Kailos GATK raw | 54 | 1 | 0 | 100% | 98.2% |
| Scrubbed BAM vs Kailos filtered | 54 | 1 | 0 | 100% | 98.2% |

**Key findings:**
- Starting from FASTQs, sarek calls no false positives (100% precision) but misses 25 variants (53.7% recall) — all in complex PGX genes (CYP2D6, CYP2C, DPYD, SLCO1B1)
- Starting from the Kailos scrubbed BAM, sarek matches 100% of Kailos calls with only 1 extra call in CYP2D6
- The 25 missed variants are entirely due to the missing scrubbing step, not the variant caller
- GATK raw vs Kailos filtered makes no difference — the filtered variants all pass Kailos's own filter

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `incompatible contigs` at BQSR | Add `--igenomes_ignore` and supply all hg19 reference paths explicitly |
| `BWAMEM2_INDEX` OOM killed (exit 137) | Use `--aligner bwa-mem` — BWA-MEM2 index building requires ~32 GB Docker memory; the hg19 BWA v1 index already exists and avoids this entirely |
| `No valid UMI found in read name` | Add `&& !params.umi_read_structure` fix to `fastq_preprocess_gatk/main.nf` (custom fix #4 above) |
| Multi-lane sample stalls after ALIGN_UMI | Apply `sample_lane_id` groupTuple fix to `fastq_create_umi_consensus_fgbio/main.nf` (custom fix #3 above) |
| `Cannot extract flowcell ID` warning | Safe to ignore — test data has non-standard FASTQ headers |
