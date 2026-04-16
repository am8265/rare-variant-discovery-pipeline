# VEP Annotation Workflow

Ensembl VEP annotation workflow for variant functional annotation.

## Overview

Runs Ensembl Variant Effect Predictor (VEP) on a VCF to add functional annotations including consequence, gene symbol, HGVS notation, population frequencies, and pathogenicity scores.

## Workflow Steps

1. **ExtractVEPCache** — unpack VEP cache from tar.gz
2. **RunVEP** — annotate VCF with VEP (offline mode, using cache)
3. **ConvertVEPToTable** — extract CSQ field to TSV table

## Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `input_vcf` | File | Input VCF (can be "fake" sites-only VCF) |
| `input_vcf_index` | File | Tabix index |
| `vep_cache_tar_gz` | File | VEP cache archive (homo_sapiens_vep_110_GRCh38.tar.gz) |
| `genome_assembly` | String | GRCh38 or GRCh37 |
| `output_prefix` | String | Output file prefix |

## Outputs

| File | Description |
|------|-------------|
| `annotated_vcf` | VCF with VEP CSQ field |
| `annotation_table` | TSV with extracted annotations |
| `vep_summary` | HTML summary report |

## Annotations Included

- **Consequence:** missense, LoF, splice, synonymous, etc.
- **Gene:** symbol, Ensembl ID, biotype
- **Transcript:** Feature ID, HGVS notation (c. and p.)
- **gnomAD AF:** overall + population-specific frequencies
- **ClinVar:** clinical significance
- **Pathogenicity scores:** CADD, REVEL, PolyPhen, SIFT

## Usage

```bash
# Create inputs JSON
cat > inputs.json <<EOF
{
  "VEPAnnotation.input_vcf": "s3://bucket/rare_variants_sites_only.vcf.gz",
  "VEPAnnotation.input_vcf_index": "s3://bucket/rare_variants_sites_only.vcf.gz.tbi",
  "VEPAnnotation.vep_cache_tar_gz": "s3://bucket/vep_cache_110.tar.gz",
  "VEPAnnotation.genome_assembly": "GRCh38",
  "VEPAnnotation.output_prefix": "rare_variants_vep"
}
EOF

# Run with Cromwell
java -jar cromwell.jar run vep_annotate.wdl -i inputs.json

# Or submit to AWS HealthOmics
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --parameters file://inputs.json \
  --output-uri s3://bucket/outputs/
```

## Runtime

- **VEP annotation:** ~2-4 hours for 1M variants
- **Cost:** ~$5-10 (AWS HealthOmics)

## Notes

- VEP cache must be pre-downloaded (60-80 GB for GRCh38)
- Runs in offline mode (no internet required)
- Fork=4 for parallel processing
- TSV output has one row per variant-transcript pair (1:many)
- For analysis, usually filter to canonical transcripts or highest impact
