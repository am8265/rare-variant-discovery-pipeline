-- 01_variant_summary.sql
-- Aggregate multi-sample VCF into variant summary table
-- Input: normalized VCF imported to AWS Variant Store (Parquet format)
-- Output: variant_summary_table with one row per variant_id

WITH variant_genotypes AS (
  -- Extract genotypes and filter for PASS variants with lad >= 20
  SELECT
    CONCAT(chr, '-', pos, '-', ref, '-', alt) AS variant_id,
    chr,
    pos,
    ref,
    alt,
    filter,
    sample_id,
    gt,
    ad,
    dp,
    gq,
    lad
  FROM variant_store.normalized_vcf
  WHERE
    filter = 'PASS'
    AND lad >= 20
),

genotype_counts AS (
  -- Count hom/het genotypes per variant
  SELECT
    variant_id,
    chr,
    pos,
    ref,
    alt,
    COUNT(DISTINCT sample_id) AS total_samples,
    COUNT(CASE WHEN gt = '1/1' OR gt = '1|1' THEN 1 END) AS no_of_homs,
    COUNT(CASE WHEN gt = '0/1' OR gt = '1/0' OR gt = '0|1' OR gt = '1|0' THEN 1 END) AS no_of_hets,
    AVG(CAST(lad AS DOUBLE)) AS avg_lad,
    AVG(CAST(dp AS DOUBLE)) AS avg_dp,
    AVG(CAST(gq AS DOUBLE)) AS avg_gq
  FROM variant_genotypes
  GROUP BY variant_id, chr, pos, ref, alt
)

-- Final variant summary table
SELECT
  variant_id,
  chr,
  pos,
  ref,
  alt,
  total_samples,
  no_of_homs,
  no_of_hets,
  avg_lad,
  avg_dp,
  avg_gq,
  -- Calculate allele count and frequency
  (no_of_homs * 2 + no_of_hets) AS allele_count,
  CAST((no_of_homs * 2 + no_of_hets) AS DOUBLE) / (total_samples * 2) AS cohort_af
FROM genotype_counts
ORDER BY chr, pos;

-- Output: s3://chop-genomics/variant-summary/variant_summary_table/
-- Format: Parquet, partitioned by chr
