# Joint Genotyping Workflow

GATK-based joint genotyping workflow for cohort-level variant calling.

## Overview

Merges per-sample GVCFs and performs joint genotyping across the entire cohort to improve variant quality and allele frequency estimates.

## Workflow Steps

1. **CombineGVCFs** — merge per-sample GVCFs (scatter per chromosome)
2. **GenotypeGVCFs** — joint genotyping across cohort
3. **GatherVcfs** — merge chromosome-level VCFs
4. **VQSR** (if cohort ≥ 30 samples) — SNP + Indel variant quality score recalibration
5. **HardFilter** (if cohort < 30 samples) — QD, FS, MQ, MQRankSum, ReadPosRankSum filters

## Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `input_gvcfs` | Array[File] | Per-sample GVCF files from DRAGEN |
| `input_gvcf_indices` | Array[File] | Tabix indices (.tbi) |
| `ref_fasta` | File | Reference genome (hg38) |
| `cohort_name` | String | Output prefix |
| `use_vqsr` | Boolean | true if cohort ≥ 30 samples |

## Outputs

| File | Description |
|------|-------------|
| `joint_vcf` | Multi-sample VCF with per-sample genotypes |
| `joint_vcf_index` | Tabix index |

## Usage

```bash
# Create inputs JSON
cat > inputs.json <<EOF
{
  "JointGenotyping.input_gvcfs": ["s3://bucket/sample1.g.vcf.gz", ...],
  "JointGenotyping.input_gvcf_indices": ["s3://bucket/sample1.g.vcf.gz.tbi", ...],
  "JointGenotyping.ref_fasta": "s3://broad-references/hg38/v0/Homo_sapiens_assembly38.fasta",
  "JointGenotyping.cohort_name": "my_cohort",
  "JointGenotyping.use_vqsr": true
}
EOF

# Run with Cromwell (local)
java -jar cromwell.jar run joint_genotype.wdl -i inputs.json

# Or submit to AWS HealthOmics
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --parameters file://inputs.json \
  --output-uri s3://bucket/outputs/
```

## Runtime

- **Per chromosome:** ~30 min for 100 samples
- **Full cohort (23 chromosomes):** ~2-3 hours (parallelized)
- **Cost:** ~$10-15 for 100 WGS samples (AWS HealthOmics)

## Notes

- Scatters by chromosome for parallelism
- VQSR recommended for cohorts ≥ 30 samples
- Hard filters used for smaller cohorts (no training data for VQSR)
- Output VCF retains per-sample genotype columns (GT, DP, GQ, AD)
