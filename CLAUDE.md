# CLAUDE.md - kailos-sarek

## Project Overview

This is **KailosGenetics' fork of nf-core/sarek v3.8.0**, a Nextflow DSL2 pipeline for detecting germline and somatic variants from whole genome or targeted sequencing data. Currently a clean fork with no Kailos-specific modifications — tracks upstream nf-core/sarek exactly.

- **Language**: Nextflow DSL2 (Groovy-based), with Python/Bash helpers
- **Nextflow version**: >=25.10.2
- **nf-core template**: 3.5.1
- **Remote**: `git@github.com:KailosGenetics/kailos-sarek.git`
- **Default branch**: master

## Repository Structure

```
main.nf                      # Entry point - orchestrates NFCORE_SAREK workflow
workflows/sarek/main.nf      # Core SAREK workflow logic
subworkflows/local/          # 69 local subworkflows (preprocessing, variant calling, annotation)
subworkflows/nf-core/        # 7 nf-core community subworkflows
modules/local/               # 4 custom modules (add_info_to_vcf, consensus_from_sites, create_intervals_bed, samtools/reindex_bam)
modules/nf-core/             # ~90 nf-core community modules (pinned via modules.json)
conf/                        # Configuration files
  base.config                #   Process resource requirements (CPU/mem/time labels)
  igenomes.config            #   Reference genome paths (iGenomes)
  modules/                   #   40 module-specific config files
  test*.config               #   Test profiles (test, test_full, test_full_germline, test_mutect2)
tests/                       # 59 nf-test files + snapshots
bin/                         # Helper scripts (license_message.py)
assets/                      # Templates, schemas, varlociraptor scenarios
docs/                        # Usage docs, output docs, variant calling guides
```

## Pipeline Execution Flow

```
Input (FASTQ/BAM/CRAM) -> Preprocessing -> Variant Calling -> Post-Processing -> Annotation -> QC
```

**Entry via `--step` parameter**:
- `mapping` (default): Full pipeline from FASTQ alignment
- `markduplicates`: Start from duplicate marking
- `prepare_recalibration`: Start from BQSR preparation
- `recalibrate`: Start from recalibrated BAMs
- `variant_calling`: Start from variant calling on CRAM/BAM
- `annotate`: Annotate existing VCFs

**Key parameters**:
- `--input`: Samplesheet CSV (patient, sample, lane, fastq_1, fastq_2)
- `--tools`: Comma-separated variant callers (haplotypecaller, mutect2, strelka, deepvariant, manta, cnvkit, etc.)
- `--aligner`: bwa-mem (default), bwa-mem2, dragmap, parabricks
- `--genome`: Reference genome (default: GATK.GRCh38)
- `--wes`: Flag for exome/targeted sequencing data
- `--skip_tools`: Tools to skip (fastqc, markduplicates, baserecalibrator, multiqc)

## Variant Calling Tools

| Category | Tools |
|----------|-------|
| SNV/Indel (germline) | HaplotypeCaller, DeepVariant, Freebayes, Sentieon DNAscope/Haplotyper, Strelka, Lofreq |
| SNV/Indel (somatic) | Mutect2, Strelka, MuSE, Sentieon TNscope, Freebayes |
| Structural variants | Manta, TIDDIT |
| Copy number | CNVkit, Control-FREEC, ASCAT |
| Microsatellite instability | MSIsensor2, MSIsensor-pro |
| Other | mpileup, indexcov |
| Post-processing | Varlociraptor, bcftools (filter/norm/concat/consensus) |
| Annotation | SnpEff, Ensembl VEP, BCFtools annotate, SnpSift |

## Development

### Building & Running

```bash
# Run with test profile
nextflow run main.nf -profile test,docker --outdir results

# Run with specific tools
nextflow run main.nf -profile docker \
  --input samplesheet.csv \
  --tools haplotypecaller,strelka \
  --outdir results

# Resume a failed run
nextflow run main.nf -resume
```

### Testing

**Framework**: nf-test v0.9.3 with snapshot testing

```bash
# Run all tests
nf-test test --profile +docker --ci --verbose

# Run specific test
nf-test test tests/aligner-bwa-mem.nf.test --profile +docker --ci --verbose

# Run with tags
nf-test test --profile +docker --tag cpu --ci --verbose

# Run with sharding (for CI parallelism)
nf-test test --profile +docker --shard 1/15 --ci --verbose
```

**nf-test plugins**: nft-bam@0.4.0, nft-utils@0.0.8, nft-vcf@1.0.7

Test files live in `tests/` with `.nf.test` extension and `.nf.test.snap` snapshot files. Tests use the `test` config profile which provides minimal test datasets.

### Linting

```bash
# Pre-commit hooks (Prettier formatting + whitespace fixes)
pre-commit run --all-files

# nf-core pipeline linting
nf-core pipelines lint
```

**Prettier config**: printWidth 120, tabWidth 4 (2 for md/yml/html/css/js)

### CI/CD (GitHub Actions)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| nf-test.yml | PR, release | Main test suite (docker/conda/singularity x 2 NF versions, up to 15 shards) |
| nf-test-gpu.yml | PR, release | GPU tests (parabricks, etc.) |
| linting.yml | PR | pre-commit + nf-core lint |
| fix_linting.yml | PR comment | Auto-fix lint via `@nf-core-bot fix linting` |
| cloudtest.yml | PR approval, release | Full tests on AWS/Azure via Seqera Platform |
| ncbench.yml | Manual | Benchmark uploads to Zenodo |
| branch.yml | PR | Ensures PRs to master come from dev |

### Module Management

nf-core modules are tracked in `modules.json` with pinned git SHAs. To update:

```bash
# List installed modules
nf-core modules list local

# Update a module
nf-core modules update <tool_name>

# Install a new module
nf-core modules install <tool_name>
```

Local modules go in `modules/local/`. nf-core modules go in `modules/nf-core/` and should not be edited directly.

### Adding New Features

Per CONTRIBUTING.md conventions:
- Initial process channels: `ch_output_from_<process>`
- Intermediate channels: `ch_<previousprocess>_for_<nextprocess>`
- New parameters go in `nextflow.config` with defaults, then update `nextflow_schema.json`
- Module configs go in `conf/modules/<tool>.config`
- Write nf-test tests for new functionality

## Configuration Hierarchy

1. `nextflow.config` - Base params and profile definitions
2. `conf/base.config` - Process resource labels (process_single/low/medium/high/high_memory/long)
3. `conf/modules/*.config` - Per-module ext.args, publishDir, etc.
4. `conf/igenomes.config` - Reference genome paths
5. Test configs (`conf/test*.config`) - Override params for testing
6. Custom institutional configs loaded from `params.custom_config_base`

### Resource Labels

| Label | CPUs | Memory | Time |
|-------|------|--------|------|
| process_single | 1 | 6 GB | 8h |
| process_low | 2 | 12 GB | 8h |
| process_medium | 6 | 36 GB | 16h |
| process_high | 12 | 72 GB | 32h |
| process_long | - | - | 40h |
| process_high_memory | - | 200 GB | - |

## Container Profiles

Supported: docker, singularity, apptainer, conda, mamba, podman, shifter, charliecloud, wave

Default container registry: `quay.io`

## Key Files

| File | Purpose |
|------|---------|
| `main.nf` | Pipeline entry point |
| `workflows/sarek/main.nf` | Core workflow logic (~600 lines) |
| `nextflow.config` | All parameters and profiles |
| `nextflow_schema.json` | Parameter schema for validation (91KB) |
| `modules.json` | Tracks nf-core module versions |
| `nf-test.config` | Test framework configuration |
| `.nf-core.yml` | nf-core template metadata and lint rules |
| `tower.yml` | Seqera Platform report definitions |

## Nextflow Plugins

- `nf-core-utils@0.4.0` - Pipeline utilities
- `nf-fgbio@1.0.0` - UMI read structure validation
- `nf-prov@1.2.2` - Provenance reports
- `nf-schema@2.6.1` - Parameter validation
