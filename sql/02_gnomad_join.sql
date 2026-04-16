-- 02_gnomad_join.sql
-- LEFT JOIN variant_summary_table with gnomAD
-- Filter for rare variants (gnomAD AF_joint < 0.01 or absent from gnomAD)
-- Input: variant_summary_table + gnomAD imported to AWS Variant Store
-- Output: rare_variant_summary_table

WITH gnomad_lookup AS (
  -- gnomAD table structure (imported to Variant Store)
  SELECT
    CONCAT(chr, '-', pos, '-', ref, '-', alt) AS variant_id,
    af_joint AS gnomad_af_joint,
    af_afr,
    af_amr,
    af_eas,
    af_nfe,
    af_sas,
    ac,
    an,
    nhomalt
  FROM gnomad.genomes_v3_1
)

SELECT
  v.variant_id,
  v.chr,
  v.pos,
  v.ref,
  v.alt,
  v.total_samples,
  v.no_of_homs,
  v.no_of_hets,
  v.avg_lad,
  v.avg_dp,
  v.avg_gq,
  v.allele_count,
  v.cohort_af,
  -- gnomAD annotations
  COALESCE(g.gnomad_af_joint, 0.0) AS gnomad_af_joint,
  g.af_afr AS gnomad_af_afr,
  g.af_amr AS gnomad_af_amr,
  g.af_eas AS gnomad_af_eas,
  g.af_nfe AS gnomad_af_nfe,
  g.af_sas AS gnomad_af_sas,
  g.ac AS gnomad_ac,
  g.an AS gnomad_an,
  g.nhomalt AS gnomad_nhomalt,
  -- Flag if novel (absent from gnomAD)
  CASE 
    WHEN g.variant_id IS NULL THEN TRUE 
    ELSE FALSE 
  END AS is_novel
FROM variant_summary_table v
LEFT JOIN gnomad_lookup g
  ON v.variant_id = g.variant_id
WHERE
  -- Rare variant filter: gnomAD AF < 1% or absent
  (g.gnomad_af_joint < 0.01 OR g.gnomad_af_joint IS NULL)
ORDER BY v.chr, v.pos;

-- Output: s3://chop-genomics/rare-variants/rare_variant_summary_table/
-- Format: Parquet, partitioned by chr
