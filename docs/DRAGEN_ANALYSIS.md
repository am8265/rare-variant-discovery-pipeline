# DRAGEN Proof-of-Concept Analysis

**My Contribution:** Evaluated DRAGEN accuracy against GATK for production adoption decision

---

## Objective

Compare DRAGEN vs GATK variant calling on GIAB benchmark samples to validate DRAGEN for production use at CHOP.

---

## Analysis Approach

### Test Dataset
- **GIAB HG002** (Ashkenazi trio son)
- **Reference truthset:** GIAB v4.2.1
- **Region:** High-confidence regions only

### Pipelines Compared
1. **DRAGEN 3.10** (ICA)
   - FASTQ → alignment → variant calling → GVCF
   
2. **GATK 4.3 Best Practices**
   - BWA-MEM alignment → MarkDuplicates → BQSR → HaplotypeCaller → GVCF

### Benchmarking Tool
- **hap.py (v0.3.12)** — Illumina variant comparison tool
- Metrics: Precision, Recall, F1-score, genotype concordance

---

## Key Results

| Variant Type | Metric | DRAGEN | GATK | 
|--------------|--------|--------|------|
| **SNPs**     | Recall | 99.8%  | 99.7% |
|              | Precision | 99.9% | 99.8% |
|              | F1-score | 99.85% | 99.75% |
| **Indels**   | Recall | 98.5%  | 97.9% |
|              | Precision | 99.1% | 98.6% |
|              | F1-score | 98.8% | 98.25% |

**Genotype concordance:** 99.95% (DRAGEN vs GATK on overlapping calls)

---

## Findings

✅ **DRAGEN matched or exceeded GATK accuracy** for both SNPs and indels

✅ **Indel calling improved** — DRAGEN showed higher recall on complex indels

✅ **Runtime:** DRAGEN 30 min vs GATK 6 hours (same WGS sample)

⚠️ **Minor discrepancies** in low-complexity regions (short tandem repeats) — both callers struggled here

---

## Cost Analysis (AWS)

Performed compute cost comparison for 100 WGS samples:

| Platform | Cost/Sample | Total (100 samples) |
|----------|-------------|---------------------|
| **DRAGEN (ICA)** | $5-8 | $500-800 |
| **GATK (EC2 c5.9xlarge)** | $3-5 | $300-500 |

**Note:** DRAGEN cost includes infrastructure (FPGA instances), GATK does not include data transfer or HealthOmics orchestration costs.

**Trade-off:** DRAGEN 20x faster, slightly higher per-sample cost, but better for high-throughput production pipelines.

---

## Recommendation

✅ **Adopt DRAGEN for production** — accuracy equivalent to GATK, significantly faster turnaround time

✅ **Use GATK for edge cases** — low-complexity regions, small cohorts where speed is not critical

---

## Impact

- CHOP adopted DRAGEN on ICA for production rare variant pipeline
- Reduced per-sample turnaround from 6 hours → 30 minutes
- Enabled processing of 10,000+ exomes/year, 2,000+ genomes/year

---

## Tools & Methods

**Variant calling:**
- DRAGEN 3.10 (ICA)
- GATK 4.3.0.0
- BWA-MEM 0.7.17

**Benchmarking:**
- hap.py v0.3.12
- GIAB truthset v4.2.1
- bcftools 1.17 for VCF manipulation

**Infrastructure:**
- ICA (Illumina Connected Analytics) for DRAGEN
- AWS EC2 c5.9xlarge for GATK
- AWS S3 for data storage
