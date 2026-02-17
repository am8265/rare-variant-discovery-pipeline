# rare-variant-discovery-pipeline

A modular, multi-cloud genomics pipeline for germline variant calling and rare variant discovery.  
with inspiration from [Children's Hospital of Philadelphia (CHOP)](https://www.chop.edu) genomics porgram.

> ⚠️ **Work in progress.** This repo is being reconstructed on open-source/non-PHI data to demonstrate pipeline architecture and software engineering practices.

---

## Architecture Overview

```
FASTQ / BAM / CRAM
        │
        ▼
┌──────────────────────────────────┐
│  ICA (Illumina Connected         │
│  Analytics)                      │
│                                  │
│  DRAGEN  →  per-sample GVCF      │
│  Joint Genotyping  →  msVCF      │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  AWS HealthOmics (WDL)           │
│                                  │
│  VT Normalization                │
│  VEP Annotation                  │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  AWS (Variant Store + Athena)    │
│                                  │
│  QC filter  →  Variant Summary   │
│  gnomAD join  →  Rare Variants   │
│  ClinVar / OMIM annotation       │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  GCP (BigQuery + Metabase)       │
│                                  │
│  Genotype–Phenotype integration  │
│  CHOP Rare Variant Browser       │
└──────────────────────────────────┘
```

---

## Repository Structure

```
rare-variant-discovery-pipeline/
├── workflows/
│   └── vt-normalization/        # VT decompose + normalize WDL workflow
└── dockerfiles/
    └── vt/                      # Docker image for vt + bcftools + htslib
```

More workflows will be added as the project grows.

---

## Workflows

### `workflows/vt-normalization`

WDL workflow for post-joint-genotyping variant normalization on AWS HealthOmics.

- Splits multi-allelic sites (`vt decompose -s`)
- Left-aligns indels to canonical position (`vt normalize`)
- Indexes output with tabix
- Scatter/gather for cohort-scale processing

→ See [`workflows/vt-normalization/README.md`](workflows/vt-normalization/README.md)

---

## Docker Images

### `dockerfiles/vt`

Builds `vt 0.57721` from source with `bcftools 1.17` and `htslib 1.17`.  
Mirrored to AWS ECR for use in HealthOmics workflows.

→ See [`dockerfiles/vt/`](dockerfiles/vt/)

---

## Stack

| Layer | Technology |
|---|---|
| Variant calling | DRAGEN (ICA) |
| Workflow engine | WDL · Cromwell · AWS HealthOmics |
| Normalization | vt · bcftools |
| Storage | AWS S3 · AWS Variant Store |
| Filtering | AWS Athena (SQL on Parquet) |
| Annotation | VEP · ClinVar · OMIM (AWS Annotation Store) |
| Warehousing | GCP BigQuery |
| Dashboard | Metabase |

---

## Status

| Component | Status |
|---|---|
| VT normalization WDL | ✅ Done |
| VT Docker image | ✅ Done |
| Joint genotyping WDL | 🔜 Planned |
| VEP annotation WDL | 🔜 Planned |
| Athena rare variant filter | 🔜 Planned |
| BigQuery ETL | 🔜 Planned |

---

## Author

**Ayan Malakar**  
Bioinformatics Scientist  
[github.com/am5153](https://github.com/am5153)
