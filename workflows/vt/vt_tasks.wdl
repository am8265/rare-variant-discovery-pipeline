version 1.0

## ============================================================
## VT Normalization Tasks
## ============================================================
## Individual WDL tasks for the VT normalization pipeline.
## Each task is self-contained with its own Docker runtime,
## retry logic, and output validation.
## ============================================================

## ────────────────────────────────────────────────────────────
## TASK 1: Decompose
## Split multi-allelic records into biallelic records.
## e.g.  chr1  100  A  T,C  →  chr1  100  A  T
##                              chr1  100  A  C
## ────────────────────────────────────────────────────────────
task Decompose {

  meta {
    description: "Split multi-allelic variants into individual biallelic records using vt decompose -s"
  }

  parameter_meta {
    input_vcf:       "Input gVCF (.vcf.gz or .g.vcf.gz)"
    input_vcf_index: "Tabix index (.tbi)"
    sample_id:       "Sample identifier"
    docker_image:    "Docker image with vt + tabix"
    disk_size_gb:    "Disk size in GB"
    memory_gb:       "Memory in GB"
    cpu:             "CPU cores"
  }

  input {
    File   input_vcf
    File   input_vcf_index
    String sample_id
    String docker_image
    Int    disk_size_gb
    Int    memory_gb
    Int    cpu
  }

  # Output filename
  String output_basename = sample_id + ".decomposed.g.vcf.gz"

  command <<<
    set -euo pipefail

    echo "[$(date)] Starting decompose for sample: ~{sample_id}"
    echo "[$(date)] Input VCF: ~{input_vcf}"

    # ── Validate input exists and is non-empty ──────────────
    if [[ ! -f "~{input_vcf}" ]]; then
      echo "ERROR: Input VCF not found: ~{input_vcf}" >&2
      exit 1
    fi

    INPUT_SIZE=$(stat -c%s "~{input_vcf}")
    echo "[$(date)] Input file size: ${INPUT_SIZE} bytes"
    if [[ "${INPUT_SIZE}" -eq 0 ]]; then
      echo "ERROR: Input VCF is empty" >&2
      exit 1
    fi

    # ── Verify index is co-located ──────────────────────────
    # tabix requires the index to be alongside the VCF
    ln -sf "~{input_vcf_index}" "~{input_vcf}.tbi" 2>/dev/null || true

    # ── Count variants before decomposition ─────────────────
    BEFORE=$(bcftools view --no-header --exclude-types ref ~{input_vcf} 2>/dev/null | wc -l || echo "unknown")
    echo "[$(date)] Variant count BEFORE decompose: ${BEFORE}"

    # ── Run vt decompose ────────────────────────────────────
    # -s  : smart decompose (preserves phase information)
    # Pipe directly to bgzip for compressed output
    vt decompose -s \
        ~{input_vcf} \
        -o - 2>decompose.log \
      | bgzip -c > ~{output_basename}

    # ── Check vt ran successfully ────────────────────────────
    VT_EXIT=${PIPESTATUS[0]}
    if [[ "${VT_EXIT}" -ne 0 ]]; then
      echo "ERROR: vt decompose failed with exit code ${VT_EXIT}" >&2
      cat decompose.log >&2
      exit 1
    fi

    # ── Index the output ────────────────────────────────────
    tabix -p vcf ~{output_basename}

    # ── Count variants after decomposition ──────────────────
    AFTER=$(bcftools view --no-header --exclude-types ref ~{output_basename} 2>/dev/null | wc -l || echo "unknown")
    echo "[$(date)] Variant count AFTER  decompose: ${AFTER}"

    # ── Print vt decompose log summary ──────────────────────
    echo "[$(date)] vt decompose log:"
    cat decompose.log

    echo "[$(date)] Decompose complete: ~{output_basename}"
  >>>

  output {
    File decomposed_vcf       = output_basename
    File decomposed_vcf_index = output_basename + ".tbi"
    File decompose_log        = "decompose.log"
  }

  runtime {
    docker:    docker_image
    memory:    memory_gb + " GB"
    cpu:       cpu
    disks:     "local-disk " + disk_size_gb + " HDD"
    maxRetries: 2
    preemptible: 2  # Use preemptible/spot for cost savings
  }
}


## ────────────────────────────────────────────────────────────
## TASK 2: Normalize
## Left-align indels and normalize variant representation.
## Requires reference genome for left-alignment.
##
## Why this matters:
##   ATTTC / del T can be written as pos 1,2,3 — vt picks pos 1
##   Ensures identical variants from different callers match
## ────────────────────────────────────────────────────────────
task Normalize {

  meta {
    description: "Left-align indels and normalize variant representation using vt normalize"
  }

  parameter_meta {
    input_vcf:       "Input VCF (decomposed or original)"
    input_vcf_index: "Tabix index (.tbi)"
    ref_fasta:       "Reference FASTA (must match VCF genome build)"
    ref_fasta_index: "Reference FASTA index (.fai)"
    sample_id:       "Sample identifier"
    docker_image:    "Docker image with vt + tabix"
    disk_size_gb:    "Disk size in GB"
    memory_gb:       "Memory in GB"
    cpu:             "CPU cores"
  }

  input {
    File   input_vcf
    File   input_vcf_index
    File   ref_fasta
    File   ref_fasta_index
    String sample_id
    String docker_image
    Int    disk_size_gb
    Int    memory_gb
    Int    cpu
  }

  String output_basename = sample_id + ".normalized.g.vcf.gz"

  command <<<
    set -euo pipefail

    echo "[$(date)] Starting normalization for sample: ~{sample_id}"

    # ── Validate inputs ──────────────────────────────────────
    for f in "~{input_vcf}" "~{ref_fasta}"; do
      if [[ ! -f "${f}" ]]; then
        echo "ERROR: Required file not found: ${f}" >&2
        exit 1
      fi
    done

    # ── Symlink index alongside VCF (tabix requirement) ─────
    ln -sf "~{input_vcf_index}" "~{input_vcf}.tbi" 2>/dev/null || true

    # ── Check ref genome build matches VCF ──────────────────
    VCF_CONTIGS=$(bcftools view -h ~{input_vcf} | grep "^##contig" | head -1 || echo "")
    echo "[$(date)] First contig header: ${VCF_CONTIGS}"

    # ── Count variants before normalization ─────────────────
    BEFORE=$(bcftools view --no-header --exclude-types ref ~{input_vcf} 2>/dev/null | wc -l || echo "unknown")
    echo "[$(date)] Variant count BEFORE normalize: ${BEFORE}"

    # ── Run vt normalize ────────────────────────────────────
    # -r  : reference FASTA for left-alignment
    # -n  : do not check VCF ordering (safe for gVCFs)
    # -o  : output file
    vt normalize \
        -r ~{ref_fasta} \
        -n \
        ~{input_vcf} \
        -o - 2>normalize.log \
      | bgzip -c > ~{output_basename}

    # ── Check vt ran successfully ────────────────────────────
    VT_EXIT=${PIPESTATUS[0]}
    if [[ "${VT_EXIT}" -ne 0 ]]; then
      echo "ERROR: vt normalize failed with exit code ${VT_EXIT}" >&2
      cat normalize.log >&2
      exit 1
    fi

    # ── Index the output ────────────────────────────────────
    tabix -p vcf ~{output_basename}

    # ── Count variants after normalization ──────────────────
    AFTER=$(bcftools view --no-header --exclude-types ref ~{output_basename} 2>/dev/null | wc -l || echo "unknown")
    echo "[$(date)] Variant count AFTER  normalize: ${AFTER}"

    # ── Validate output is not empty ────────────────────────
    OUTPUT_SIZE=$(stat -c%s "~{output_basename}")
    if [[ "${OUTPUT_SIZE}" -eq 0 ]]; then
      echo "ERROR: Output VCF is empty after normalization" >&2
      exit 1
    fi

    # ── Print normalization log ──────────────────────────────
    echo "[$(date)] vt normalize log:"
    cat normalize.log

    echo "[$(date)] Normalization complete: ~{output_basename}"
  >>>

  output {
    File normalized_vcf       = output_basename
    File normalized_vcf_index = output_basename + ".tbi"
    File normalize_log        = "normalize.log"
  }

  runtime {
    docker:      docker_image
    memory:      memory_gb + " GB"
    cpu:         cpu
    disks:       "local-disk " + disk_size_gb + " HDD"
    maxRetries:  2
    preemptible: 2
  }
}


## ────────────────────────────────────────────────────────────
## TASK 3: BcftoolsStats
## Compute per-sample QC metrics on the normalized VCF.
## Outputs a stats file for MultiQC aggregation.
## ────────────────────────────────────────────────────────────
task BcftoolsStats {

  meta {
    description: "Run bcftools stats on normalized VCF for QC metrics"
  }

  parameter_meta {
    input_vcf:    "Normalized VCF (.vcf.gz)"
    sample_id:    "Sample identifier"
    docker_image: "Docker image with bcftools"
    disk_size_gb: "Disk size in GB"
    memory_gb:    "Memory in GB"
    cpu:          "CPU cores"
  }

  input {
    File   input_vcf
    String sample_id
    String docker_image
    Int    disk_size_gb
    Int    memory_gb
    Int    cpu
  }

  String stats_file = sample_id + ".bcftools_stats.txt"

  command <<<
    set -euo pipefail

    echo "[$(date)] Running bcftools stats for sample: ~{sample_id}"

    # ── Run bcftools stats ───────────────────────────────────
    # Excludes ref-only gVCF blocks for cleaner stats
    bcftools stats \
        --exclude-types ref \
        ~{input_vcf} \
        > ~{stats_file}

    # ── Print summary section ────────────────────────────────
    echo "[$(date)] Summary statistics:"
    grep "^SN" ~{stats_file} | head -20

    # ── Extract key QC metrics ───────────────────────────────
    SNV_COUNT=$(grep "^SN" ~{stats_file} | grep "number of SNPs"   | awk '{print $NF}')
    IND_COUNT=$(grep "^SN" ~{stats_file} | grep "number of indels" | awk '{print $NF}')
    TITV=$(grep "^SN" ~{stats_file} | grep "Ts/Tv ratio"           | awk '{print $NF}')

    echo "[$(date)] SNVs:       ${SNV_COUNT}"
    echo "[$(date)] Indels:     ${IND_COUNT}"
    echo "[$(date)] Ts/Tv ratio: ${TITV}"

    # ── Validate Ti/Tv ratio (WGS ~2.0-2.1, WES ~3.0-3.3) ──
    # Warn only — do not fail (gVCF may include non-PASS sites)
    TITV_INT=$(echo "${TITV}" | cut -d'.' -f1)
    if [[ "${TITV_INT}" -lt 1 ]] || [[ "${TITV_INT}" -gt 5 ]]; then
      echo "WARNING: Unusual Ts/Tv ratio: ${TITV}. Check sample quality." >&2
    fi

    echo "[$(date)] Stats complete: ~{stats_file}"
  >>>

  output {
    File stats = stats_file
  }

  runtime {
    docker:      docker_image
    memory:      memory_gb + " GB"
    cpu:         cpu
    disks:       "local-disk " + disk_size_gb + " HDD"
    maxRetries:  1
    preemptible: 2
  }
}
