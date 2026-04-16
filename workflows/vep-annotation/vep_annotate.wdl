version 1.0

## VEP annotation workflow for rare variant summary table
## Input: "fake" VCF with unique variant sites only (no genotypes)
## Output: VEP-annotated table with consequence, gnomAD AF, CADD, ClinVar, etc.

workflow VEPAnnotation {
  input {
    File input_vcf
    File input_vcf_index
    File vep_cache_tar_gz
    String genome_assembly = "GRCh38"
    String output_prefix
  }

  call ExtractVEPCache {
    input:
      cache_tar_gz = vep_cache_tar_gz
  }

  call RunVEP {
    input:
      vcf = input_vcf,
      vcf_index = input_vcf_index,
      cache_dir = ExtractVEPCache.cache_dir,
      genome_assembly = genome_assembly,
      output_prefix = output_prefix
  }

  call ConvertVEPToTable {
    input:
      vep_vcf = RunVEP.annotated_vcf,
      output_name = "${output_prefix}.vep_annotations.tsv"
  }

  output {
    File annotated_vcf = RunVEP.annotated_vcf
    File annotation_table = ConvertVEPToTable.output_table
    File vep_summary = RunVEP.vep_summary
  }
}

# ── TASKS ─────────────────────────────────────────────────

task ExtractVEPCache {
  input {
    File cache_tar_gz
  }

  command <<<
    mkdir -p vep_cache
    tar -xzf ~{cache_tar_gz} -C vep_cache
  >>>

  runtime {
    docker: "ensemblorg/ensembl-vep:release_110.1"
    memory: "4 GB"
    cpu: 1
    disks: "local-disk 100 HDD"
  }

  output {
    Directory cache_dir = "vep_cache"
  }
}

task RunVEP {
  input {
    File vcf
    File vcf_index
    Directory cache_dir
    String genome_assembly
    String output_prefix
  }

  command <<<
    vep \
      --input_file ~{vcf} \
      --output_file ~{output_prefix}.vep.vcf \
      --format vcf \
      --vcf \
      --cache \
      --dir_cache ~{cache_dir} \
      --assembly ~{genome_assembly} \
      --offline \
      --everything \
      --fork 4 \
      --compress_output bgzip \
      --stats_file ~{output_prefix}.vep_summary.html \
      --force_overwrite
    
    # Index output VCF
    tabix -p vcf ~{output_prefix}.vep.vcf.gz
  >>>

  runtime {
    docker: "ensemblorg/ensembl-vep:release_110.1"
    memory: "16 GB"
    cpu: 4
    disks: "local-disk 200 HDD"
  }

  output {
    File annotated_vcf = "${output_prefix}.vep.vcf.gz"
    File annotated_vcf_index = "${output_prefix}.vep.vcf.gz.tbi"
    File vep_summary = "${output_prefix}.vep_summary.html"
  }
}

task ConvertVEPToTable {
  input {
    File vep_vcf
    String output_name
  }

  command <<<
    # Extract VEP CSQ field and convert to tab-delimited table
    bcftools +split-vep ~{vep_vcf} \
      -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t%Consequence\t%SYMBOL\t%Gene\t%Feature\t%BIOTYPE\t%EXON\t%INTRON\t%HGVSc\t%HGVSp\t%cDNA_position\t%CDS_position\t%Protein_position\t%Amino_acids\t%Codons\t%gnomAD_AF\t%gnomAD_AFR_AF\t%gnomAD_AMR_AF\t%gnomAD_EAS_AF\t%gnomAD_NFE_AF\t%gnomAD_SAS_AF\t%MAX_AF\t%CLIN_SIG\t%CADD_PHRED\t%REVEL\t%PolyPhen\t%SIFT\n' \
      > ~{output_name}
  >>>

  runtime {
    docker: "quay.io/biocontainers/bcftools:1.17--haef29d1_0"
    memory: "8 GB"
    cpu: 2
    disks: "local-disk 50 HDD"
  }

  output {
    File output_table = output_name
  }
}
