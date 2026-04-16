# End-to-End Pipeline Example

This document demonstrates the complete rare variant discovery pipeline from GVCF to annotated rare variants.

## Prerequisites

- Per-sample GVCFs from DRAGEN in S3: `s3://chop-genomics/single-sample-vcfs/`
- Reference genome: `s3://broad-references/hg38/v0/Homo_sapiens_assembly38.fasta`
- VEP cache: `s3://chop-genomics/references/vep_cache_110.tar.gz`
- gnomAD v3.1 imported to AWS Variant Store

---

## Step 1: Generate Cohort Manifest

```bash
python scripts/generate_manifest.py \
  --s3-prefix s3://chop-genomics/single-sample-vcfs/ \
  --output cohort_manifest.tsv \
  --min-samples 10

# Output: cohort_manifest.tsv
# sample_id       gvcf                                              gvcf_index
# NA12878         s3://chop-genomics/single-sample-vcfs/NA12878...  ...tbi
# NA12879         s3://chop-genomics/single-sample-vcfs/NA12879...  ...tbi
# ...
```

---

## Step 2: Joint Genotyping (ICA or HealthOmics)

### Option A: Run on ICA (production)
```bash
# ICA workflow submission (via ICA web UI or CLI)
# Input: cohort_manifest.tsv
# Workflow: joint-genotyping pipeline
# Output: s3://chop-genomics/joint-vcfs/cohort.joint.vcf.gz
```

### Option B: Run on HealthOmics (testing/development)
```bash
# Create WDL workflow
aws omics create-workflow \
  --name "joint-genotyping" \
  --engine WDL \
  --definition-zip fileb://joint-genotyping.zip \
  --parameter-template file://joint-genotyping-params.json

# Submit run
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --role-arn arn:aws:iam::123456789012:role/HealthOmicsWorkflowRole \
  --parameters file://joint-genotyping-inputs.json \
  --output-uri s3://chop-genomics/healthomics-outputs/joint-genotyping/
```

**Output:** `s3://chop-genomics/joint-vcfs/cohort.joint.vcf.gz`

---

## Step 3: VT Normalization (HealthOmics)

```bash
# Submit VT normalization workflow
bash scripts/healthomics_submit.sh run_vt_normalization

# Or manually:
aws omics start-run \
  --workflow-id <VT_WORKFLOW_ID> \
  --role-arn arn:aws:iam::123456789012:role/HealthOmicsWorkflowRole \
  --parameters '{
    "VTNormalize.input_vcf": "s3://chop-genomics/joint-vcfs/cohort.joint.vcf.gz",
    "VTNormalize.output_prefix": "cohort.normalized",
    "VTNormalize.ref_fasta": "s3://broad-references/hg38/v0/Homo_sapiens_assembly38.fasta"
  }' \
  --output-uri s3://chop-genomics/healthomics-outputs/vt-normalization/

# Monitor
aws omics get-run --id <RUN_ID>
```

**Output:** `s3://chop-genomics/normalized-vcfs/cohort.normalized.vcf.gz`

---

## Step 4: Import to AWS Variant Store

```bash
# Create Variant Store
aws omics create-variant-store \
  --name "chop-rare-variants" \
  --reference referenceArn=arn:aws:omics:us-east-1::referenceStore/1234567890/reference/GRCh38

# Import normalized VCF
aws omics start-variant-import-job \
  --destination-name "chop-rare-variants" \
  --role-arn arn:aws:iam::123456789012:role/VariantStoreRole \
  --items '[{
    "source": "s3://chop-genomics/normalized-vcfs/cohort.normalized.vcf.gz"
  }]' \
  --run-left-normalization
```

---

## Step 5: Athena SQL — Variant Aggregation

```bash
# Create external table pointing to Variant Store export
aws athena start-query-execution \
  --query-string file://sql/01_variant_summary.sql \
  --result-configuration "OutputLocation=s3://chop-genomics/athena-results/"

# Check status
aws athena get-query-execution --query-execution-id <QUERY_ID>
```

**Output:** `s3://chop-genomics/variant-summary/variant_summary_table/` (Parquet)

**Schema:**
```
variant_id        | chr22-34567-A-T
chr               | chr22
pos               | 34567
ref               | A
alt               | T
total_samples     | 788
no_of_homs        | 0
no_of_hets        | 2
avg_lad           | 40.5
avg_dp            | 45.2
avg_gq            | 99
allele_count      | 2
cohort_af         | 0.00127
```

---

## Step 6: Athena SQL — gnomAD Join + Rare Variant Filter

```bash
aws athena start-query-execution \
  --query-string file://sql/02_gnomad_join.sql \
  --result-configuration "OutputLocation=s3://chop-genomics/athena-results/"
```

**Output:** `s3://chop-genomics/rare-variants/rare_variant_summary_table/` (Parquet)

**Filters applied:**
- gnomAD AF_joint < 0.01 OR absent from gnomAD
- Retains ~2-5% of original variants (typical for rare variant studies)

---

## Step 7: Convert Rare Variants to "Fake VCF" for VEP

```bash
# Extract unique variant sites only (no genotypes)
bcftools view \
  --samples ^ALL \
  --output-type z \
  --output rare_variants_sites_only.vcf.gz \
  s3://chop-genomics/normalized-vcfs/cohort.normalized.vcf.gz \
  --regions-file <(awk '{print $2":"$3}' rare_variant_summary_table.tsv)

# Index
tabix -p vcf rare_variants_sites_only.vcf.gz

# Upload
aws s3 cp rare_variants_sites_only.vcf.gz s3://chop-genomics/rare-variants/
aws s3 cp rare_variants_sites_only.vcf.gz.tbi s3://chop-genomics/rare-variants/
```

---

## Step 8: VEP Annotation (HealthOmics)

```bash
aws omics start-run \
  --workflow-id <VEP_WORKFLOW_ID> \
  --role-arn arn:aws:iam::123456789012:role/HealthOmicsWorkflowRole \
  --parameters '{
    "VEPAnnotation.input_vcf": "s3://chop-genomics/rare-variants/rare_variants_sites_only.vcf.gz",
    "VEPAnnotation.vep_cache_tar_gz": "s3://chop-genomics/references/vep_cache_110.tar.gz",
    "VEPAnnotation.genome_assembly": "GRCh38",
    "VEPAnnotation.output_prefix": "rare_variants_vep"
  }' \
  --output-uri s3://chop-genomics/healthomics-outputs/vep-annotation/
```

**Output:** 
- `rare_variants_vep.vep.vcf.gz` (annotated VCF)
- `rare_variants_vep.vep_annotations.tsv` (table format)

---

## Step 9: Athena SQL — VEP Integration

```bash
# Load VEP annotation table to Athena
aws athena start-query-execution \
  --query-string "
    CREATE EXTERNAL TABLE vep_output.annotation_table (
      chrom STRING,
      pos INT,
      ref STRING,
      alt STRING,
      consequence STRING,
      symbol STRING,
      gene STRING,
      -- ... (full schema from VEP output)
    )
    ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
    LOCATION 's3://chop-genomics/healthomics-outputs/vep-annotation/'
  "

# Run integration query
aws athena start-query-execution \
  --query-string file://sql/03_vep_integration.sql \
  --result-configuration "OutputLocation=s3://chop-genomics/athena-results/"
```

**Output:** `s3://chop-genomics/rare-variants/rare_variant_annotated_table/`

---

## Step 10: ClinVar + OMIM Annotation (AWS Annotation Store)

```bash
# Annotate with ClinVar
aws omics start-annotation-import-job \
  --destination-name "rare-variants-annotated" \
  --role-arn arn:aws:iam::123456789012:role/AnnotationStoreRole \
  --items '[{
    "source": "s3://chop-genomics/rare-variants/rare_variant_annotated_table/"
  }]' \
  --format-options '{
    "vcfOptions": {
      "annotationFileFormat": "VCF"
    }
  }'

# Query annotated results
aws omics list-annotations \
  --annotation-store-name "rare-variants-annotated" \
  --filter '{
    "variantPositions": [
      {"referenceSequence": "chr22", "start": 34567}
    ]
  }'
```

---

## Step 11: Export to GCP BigQuery

```bash
# Transfer Parquet to GCS
gsutil -m rsync -r \
  s3://chop-genomics/rare-variants/rare_variant_clinically_annotated_table/ \
  gs://chop-genomics/rare-variants/

# Load to BigQuery
bq load \
  --source_format=PARQUET \
  --replace \
  --clustering_fields=gene_symbol,patient_id \
  --time_partitioning_field=call_date \
  chop-genomics.production.rare_variants \
  gs://chop-genomics/rare-variants/*.parquet
```

---

## Output Summary

| Step | Output | Location | Format |
|------|--------|----------|--------|
| Joint Genotyping | Multi-sample VCF | `s3://*/joint-vcfs/` | VCF.gz |
| VT Normalization | Normalized VCF | `s3://*/normalized-vcfs/` | VCF.gz |
| Variant Summary | Aggregated table | `s3://*/variant-summary/` | Parquet |
| Rare Variants | Filtered table | `s3://*/rare-variants/` | Parquet |
| VEP Annotation | Annotated table | `s3://*/vep-annotation/` | TSV + Parquet |
| Final Table | Clinical annotations | `s3://*/rare-variants-annotated/` | Parquet |
| BigQuery | Analysis-ready | `chop-genomics.production.rare_variants` | BigQuery table |

---

## Validation

```bash
# Check row counts
aws athena start-query-execution \
  --query-string "
    SELECT 
      'variant_summary' AS table_name, COUNT(*) AS row_count 
    FROM variant_summary_table
    UNION ALL
    SELECT 
      'rare_variants', COUNT(*) 
    FROM rare_variant_summary_table
    UNION ALL
    SELECT 
      'annotated', COUNT(*) 
    FROM rare_variant_annotated_table
  "

# Typical numbers for 788 WGS samples:
# variant_summary:  ~50M variants
# rare_variants:    ~1-2M variants (2-4%)
# annotated:        ~1-2M variants (same, with VEP/ClinVar)
```
