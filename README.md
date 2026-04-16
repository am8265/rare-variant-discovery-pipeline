# rare-variant-discovery-pipeline

**Demonstration of genomics pipeline contributions from CHOP rare variant program.**

> 📌 **Portfolio Reconstruction** — I contributed to components of a production rare variant pipeline at Children's Hospital of Philadelphia. The original codebase is proprietary. This repo contains **reconstructed examples** of my specific contributions, built on open-source data (GIAB) to demonstrate technical skills.

---

## My Contributions

At CHOP, I worked on a multi-cloud rare variant discovery pipeline as part of a bioinformatics team. My specific contributions included:

### 1. VT Normalization Workflow
- Built WDL workflow for post-joint-genotyping variant normalization
- Created Docker image (vt + bcftools) hosted on AWS ECR
- Integrated with AWS HealthOmics for production runs
- Validated against GIAB HG002 truthset

### 2. Athena SQL Data Engineering
- Wrote variant aggregation queries (GROUP BY variant_id → homs/hets/cohort AF)
- Implemented gnomAD LEFT JOIN with rare variant filter (AF < 1%)
- Optimized query performance on Parquet-partitioned data

### 3. Dashboard Feature Development
- Added new visualization features to Metabase dashboard (Python - proprietary code)
- Implemented gene-level aggregation views
- Built QC metric calculators for pipeline monitoring

### 4. Pipeline Testing & Validation
- GIAB benchmarking workflows
- Ti/Tv ratio validation
- Cohort-level QC metrics
- **DRAGEN vs GATK accuracy comparison (hap.py)**
- **AWS compute cost analysis (ICA vs EC2)**

### 5. Post-DRAGEN Sample QC
- Automated sample-level QC checks (coverage, mapping rate, Ti/Tv)
- Cohort QC aggregation script
- Manifest generation for joint genotyping (PASS samples only)

---

## Pipeline Context

The full production pipeline (team effort, CHOP proprietary):
- **Input:** WGS/WES FASTQ from partner labs
- **Variant Calling:** DRAGEN (ICA) + GATK (HealthOmics)
- **Processing:** Joint genotyping → VT normalization → VEP annotation
- **Filtering:** AWS Variant Store + Athena SQL
- **Annotation:** ClinVar + OMIM via AWS Annotation Store
- **Warehousing:** GCP BigQuery
- **Visualization:** Metabase dashboards

My role focused on workflow development (WDL), data engineering (SQL), and dashboard enhancements (Python).

---

## Testing & Validation

Components in this repo were tested on:
- **GIAB HG002** (Ashkenazi trio) — chr22 subset for rapid iteration
- **1000 Genomes** — NA12878 family trio
- **Synthetic test data** — generated with `generate_test_gvcf.py`

Validation metrics matched production expectations:
- Ti/Tv ratio: ~2.0-2.1 (WGS), ~3.0-3.3 (WES)
- Het/hom ratio: expected ranges per population
- Rare variant yield: 2-4% of total variants post-gnomAD filter

---

## Repository Structure

```
rare-variant-discovery-pipeline/
├── workflows/
│   ├── vt-normalization/          # VT decompose + normalize (WDL)
│   ├── joint-genotyping/          # GATK joint genotyping + VQSR (WDL)
│   └── vep-annotation/            # Ensembl VEP functional annotation (WDL)
├── sql/
│   ├── 01_variant_summary.sql     # Aggregate multi-sample VCF → variant summary table
│   ├── 02_gnomad_join.sql         # gnomAD LEFT JOIN → rare variant filter
│   └── 03_vep_integration.sql     # VEP annotation integration
├── scripts/
│   ├── healthomics_submit.sh      # AWS HealthOmics workflow submission examples
│   ├── generate_manifest.py       # Cohort manifest generator (scan S3 for GVCFs)
│   ├── post_dragen_qc.sh          # Sample-level QC after DRAGEN
│   └── aggregate_sample_qc.py     # Cohort QC aggregation + manifest builder
├── docs/
│   └── DRAGEN_ANALYSIS.md         # DRAGEN vs GATK accuracy + cost analysis
└── examples/
    └── end_to_end_example.md      # Complete pipeline walkthrough with real commands
```

---

## Workflows

### 1. Joint Genotyping (`workflows/joint-genotyping/`)

GATK-based cohort-level joint genotyping with VQSR.

**Input:** Per-sample GVCFs from DRAGEN  
**Output:** Multi-sample VCF with genotypes  
**Runtime:** 2-3 hours for 100 WGS samples (parallelized by chromosome)

```bash
# Example submission
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --parameters file://joint-genotyping-inputs.json \
  --output-uri s3://bucket/outputs/
```

→ See [`workflows/joint-genotyping/README.md`](workflows/joint-genotyping/README.md)

---

### 2. VT Normalization (`workflows/vt-normalization/`)

Post-joint-genotyping variant normalization (decompose multi-allelics + left-align indels).

**Input:** Multi-sample VCF from joint genotyping  
**Output:** Normalized VCF (canonical variant representation)  
**Runtime:** 30-60 min for 50M variants

→ See [`workflows/vt-normalization/README.md`](workflows/vt-normalization/README.md)

---

### 3. VEP Annotation (`workflows/vep-annotation/`)

Ensembl VEP functional annotation with gnomAD, ClinVar, CADD, REVEL.

**Input:** "Fake" VCF (sites-only, no genotypes)  
**Output:** VEP-annotated VCF + TSV table  
**Runtime:** 2-4 hours for 1M rare variants

→ See [`workflows/vep-annotation/README.md`](workflows/vep-annotation/README.md)

---

## SQL Queries (AWS Athena)

### Variant Aggregation (`sql/01_variant_summary.sql`)

Aggregates multi-sample VCF → one row per variant.

**Output schema:**
```sql
variant_id     | chr22-34567-A-T
no_of_homs     | 0
no_of_hets     | 2
avg_lad        | 40.5
cohort_af      | 0.00127
```

### gnomAD Rare Variant Filter (`sql/02_gnomad_join.sql`)

LEFT JOIN with gnomAD v3.1 → filter AF < 1%.

**Filters:** gnomAD AF_joint < 0.01 OR absent from gnomAD  
**Output:** Typically 2-4% of original variants

### VEP Integration (`sql/03_vep_integration.sql`)

Joins VEP annotations with rare variant summary table.

**Adds:** consequence, gene_symbol, HGVS, CADD, ClinVar, pathogenicity scores

---

## Tech Stack

| Layer | Technology |
|---|---|
| Variant calling | DRAGEN (ICA) · GATK Best Practices |
| Workflow engine | WDL 1.0 · Cromwell · AWS HealthOmics |
| Normalization | vt 0.57721 · bcftools 1.17 |
| Storage | AWS S3 · AWS Variant Store |
| Filtering | AWS Athena (Presto SQL on Parquet) |
| Annotation | Ensembl VEP 110 · ClinVar · OMIM (AWS Annotation Store) |
| Warehousing | GCP BigQuery |
| Visualization | Metabase |
| CI/CD | GitHub Actions · Docker · AWS ECR |

---

## Getting Started

### Run End-to-End Example

Complete walkthrough from GVCFs → annotated rare variants:

→ [`examples/end_to_end_example.md`](examples/end_to_end_example.md)

### Submit Workflows to AWS HealthOmics

```bash
# Generate cohort manifest
python scripts/generate_manifest.py \
  --s3-prefix s3://bucket/gvcfs/ \
  --output cohort_manifest.tsv

# Submit joint genotyping
bash scripts/healthomics_submit.sh run_joint_genotyping

# Submit VT normalization
bash scripts/healthomics_submit.sh run_vt_normalization

# Submit VEP annotation
bash scripts/healthomics_submit.sh run_vep_annotation
```

### Run Athena SQL Queries

```bash
# Variant aggregation
aws athena start-query-execution \
  --query-string file://sql/01_variant_summary.sql \
  --result-configuration "OutputLocation=s3://bucket/athena-results/"

# gnomAD join + rare variant filter
aws athena start-query-execution \
  --query-string file://sql/02_gnomad_join.sql \
  --result-configuration "OutputLocation=s3://bucket/athena-results/"

# VEP integration
aws athena start-query-execution \
  --query-string file://sql/03_vep_integration.sql \
  --result-configuration "OutputLocation=s3://bucket/athena-results/"
```

---

## Validation

Tested on:
- 1000 Genomes chr22 trio (NA12878 family)
- GIAB HG002 truthset benchmarking
- CHOP internal cohort (788 WGS samples) — output metrics validated against publication data

Expected outputs:
- Variant summary: ~50M variants (full WGS cohort)
- Rare variants: ~1-2M variants (2-4% after gnomAD filter)
- High-impact rare: ~10-20k variants (LoF + splice)

---

## Project Status

| Component | Status |
|---|---|
| VT normalization WDL | ✅ Complete |
| Joint genotyping WDL | ✅ Complete |
| VEP annotation WDL | ✅ Complete |
| Athena SQL queries | ✅ Complete |
| AWS HealthOmics examples | ✅ Complete |
| End-to-end documentation | ✅ Complete |
| CI/CD (GitHub Actions) | 🔜 Planned |
| BigQuery ETL | 🔜 Planned |
| Metabase dashboard | 🔜 Planned |

---

## Author

**Ayan Malakar**  
Senior Bioinformatics Scientist  
9 years NGS pipeline development · AWS · GCP · WDL · SQL

[GitHub](https://github.com/am5153) · [LinkedIn](https://linkedin.com/in/ayanmalakar)

---

## License

Code samples for portfolio/demonstration purposes. Original workflows developed at CHOP.
