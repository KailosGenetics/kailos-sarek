#### What is main.nf?

In Nextflow, main.nf is the conventional entry point file — like main.py or index.js in other ecosystems. There are lots of main.nf files in this repo because every module and subworkflow has its own. They form a hierarchy:

The three levels of `main.nf`

1. `./main.nf` (root) — The entry point. This is what Nextflow executes when you run nextflow run main.nf.
2. `workflows/sarek/main.nf` — The core workflow. Contains the actual pipeline logic (preprocessing, variant calling, annotation, QC).
3. `modules/*/main.nf` and `subworkflows/*/main.nf` (~170 files) — Individual tool wrappers and subworkflows. Each one runs a single bioinformatics tool (e.g., bwa/mem, gatk4/haplotypecaller, fastqc).

What the root main.nf does

Reading top to bottom, it has four sections:

#### 1. Genome parameter setup (lines 27-62)

Loads reference genome paths (fasta, bwa index, dbSNP, etc.) from a genome config. The getGenomeAttribute() function at the bottom (line 405) looks up values from params.genomes[params.genome], which comes from conf/igenomes.config. This means you say --genome GATK.GRCh38 and all the reference file paths get filled in automatically.

#### 2. NFCORE_SAREK named workflow (lines 88-343)

This is the "orchestration layer" that prepares everything before the real analysis:
- PREPARE_GENOME — Builds/indexes reference files (BWA index, samtools faidx, etc.) if they don't already exist
- PREPARE_INTERVALS — Splits the genome into intervals for scatter/gather parallelism (this is how it runs variant calling on many chunks simultaneously)
- PREPARE_REFERENCE_CNVKIT — Builds CNVkit reference if needed
- Cache/annotation setup — Downloads or locates SnpEff/VEP annotation caches
- SAREK(...) — Calls the core workflow with all the prepared references

#### 3. The unnamed workflow block (lines 350-387)

This is the actual execution entry point (Nextflow runs unnamed workflow blocks). It does three things in sequence:
1. PIPELINE_INITIALISATION — Validates params, parses the samplesheet CSV
2. NFCORE_SAREK — Runs everything described above
3. PIPELINE_COMPLETION — Sends email notifications, runs cleanup

#### 4. output block (lines 389-393)

Declares that MultiQC reports should be published to a multiqc directory.

What `workflows/sarek/main.nf` does

This is where the actual bioinformatics happens. The flow is:

1. Input handling (lines 138-208) — Figures out if input is FASTQ, BAM, or Spring-compressed, converts as needed, runs FastQC
2. Preprocessing (lines 210-255) — Aligns reads (BWA/DragMap/Parabricks), marks duplicates, runs base quality score recalibration (BQSR)
3. Sample pairing (lines 306-394) — Separates samples into germline (normal), tumor-only, and tumor-normal pairs based on the status field in the samplesheet
4. Variant calling (lines 403-500) — Three parallel tracks:
  - BAM_VARIANT_CALLING_GERMLINE_ALL — Normal samples
  - BAM_VARIANT_CALLING_TUMOR_ONLY_ALL — Tumor without matched normal
  - BAM_VARIANT_CALLING_SOMATIC_ALL — Tumor-normal pairs
5. Post-processing (lines 516-537) — Merge, filter, normalize VCFs
6. Annotation (lines 552-582) — SnpEff, VEP, bcftools annotate, SnpSift
7. MultiQC (lines 604-631) — Aggregate all QC reports into one HTML report

The key Nextflow concept to understand is Channels — those ch_* and cram_variant_calling_* variables are asynchronous data streams, not regular variables. Data flows through them like water through pipes, and Nextflow automatically parallelizes work when data is ready. That's how the pipeline can process dozens of samples across hundreds of genome intervals concurrently.
