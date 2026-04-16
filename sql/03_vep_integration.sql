-- 03_vep_integration.sql
-- LEFT JOIN rare_variant_summary_table with VEP annotations
-- Input: rare_variant_summary_table + VEP output table (from WDL)
-- Output: rare_variant_annotated_table (ready for ClinVar/OMIM annotation)

WITH vep_annotations AS (
  -- VEP output converted to table format (from vep_annotate.wdl)
  SELECT
    CONCAT(chrom, '-', pos, '-', ref, '-', alt) AS variant_id,
    consequence,
    symbol AS gene_symbol,
    gene AS gene_id,
    feature AS transcript_id,
    biotype,
    exon,
    intron,
    hgvsc,
    hgvsp,
    cdna_position,
    cds_position,
    protein_position,
    amino_acids,
    codons,
    gnomad_af AS vep_gnomad_af,  -- may differ slightly from gnomAD table
    clin_sig AS clinvar_significance,
    cadd_phred,
    revel,
    polyphen,
    sift
  FROM vep_output.annotation_table
)

SELECT
  r.variant_id,
  r.chr,
  r.pos,
  r.ref,
  r.alt,
  -- Variant summary metrics
  r.total_samples,
  r.no_of_homs,
  r.no_of_hets,
  r.avg_lad,
  r.avg_dp,
  r.avg_gq,
  r.allele_count,
  r.cohort_af,
  -- gnomAD population frequencies
  r.gnomad_af_joint,
  r.gnomad_af_afr,
  r.gnomad_af_amr,
  r.gnomad_af_eas,
  r.gnomad_af_nfe,
  r.gnomad_af_sas,
  r.is_novel,
  -- VEP functional annotations
  v.consequence,
  v.gene_symbol,
  v.gene_id,
  v.transcript_id,
  v.biotype,
  v.hgvsc,
  v.hgvsp,
  v.protein_position,
  v.amino_acids,
  -- Pathogenicity scores
  v.cadd_phred,
  v.revel,
  v.polyphen,
  v.sift,
  v.clinvar_significance,
  -- Classify consequence severity
  CASE
    WHEN v.consequence LIKE '%stop_gained%' OR 
         v.consequence LIKE '%frameshift%' OR
         v.consequence LIKE '%splice_acceptor%' OR
         v.consequence LIKE '%splice_donor%' THEN 'high_impact'
    WHEN v.consequence LIKE '%missense%' OR
         v.consequence LIKE '%inframe%' THEN 'moderate_impact'
    WHEN v.consequence LIKE '%synonymous%' OR
         v.consequence LIKE '%intron%' THEN 'low_impact'
    ELSE 'modifier'
  END AS consequence_impact
FROM rare_variant_summary_table r
LEFT JOIN vep_annotations v
  ON r.variant_id = v.variant_id
ORDER BY r.chr, r.pos;

-- Output: s3://chop-genomics/rare-variants/rare_variant_annotated_table/
-- Format: Parquet, partitioned by chr
-- Next step: ClinVar + OMIM annotation via AWS Annotation Store
