version 1.0

## Joint genotyping workflow for cohort-level variant calling
## Input: per-sample GVCFs from DRAGEN
## Output: multi-sample VCF with genotypes across all samples
##
## Steps:
##   1. CombineGVCFs - merge all per-sample GVCFs
##   2. GenotypeGVCFs - joint genotyping across cohort
##   3. VQSR (SNPs + Indels) or hard filters if cohort < 30 samples

workflow JointGenotyping {
  input {
    Array[File] input_gvcfs
    Array[File] input_gvcf_indices
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    
    # VQSR training resources
    File hapmap_vcf
    File hapmap_vcf_index
    File omni_vcf
    File omni_vcf_index
    File onekg_vcf
    File onekg_vcf_index
    File dbsnp_vcf
    File dbsnp_vcf_index
    File mills_vcf
    File mills_vcf_index
    
    String cohort_name
    Boolean use_vqsr = true  # set false if cohort < 30 samples
  }

  # Scatter joint genotyping per chromosome for parallelism
  scatter (chrom in ["chr1", "chr2", "chr3", "chr4", "chr5", "chr6", "chr7", "chr8", 
                     "chr9", "chr10", "chr11", "chr12", "chr13", "chr14", "chr15", 
                     "chr16", "chr17", "chr18", "chr19", "chr20", "chr21", "chr22", "chrX"]) {
    
    call CombineGVCFs {
      input:
        gvcfs = input_gvcfs,
        gvcf_indices = input_gvcf_indices,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        interval = chrom,
        output_name = "${cohort_name}.${chrom}.combined.g.vcf.gz"
    }

    call GenotypeGVCFs {
      input:
        combined_gvcf = CombineGVCFs.output_gvcf,
        combined_gvcf_index = CombineGVCFs.output_gvcf_index,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        dbsnp_vcf = dbsnp_vcf,
        dbsnp_vcf_index = dbsnp_vcf_index,
        interval = chrom,
        output_name = "${cohort_name}.${chrom}.vcf.gz"
    }
  }

  call GatherVcfs {
    input:
      input_vcfs = GenotypeGVCFs.output_vcf,
      output_name = "${cohort_name}.joint.vcf.gz"
  }

  if (use_vqsr) {
    call VariantRecalibrator as RecalibrateSNPs {
      input:
        vcf = GatherVcfs.output_vcf,
        vcf_index = GatherVcfs.output_vcf_index,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        hapmap = hapmap_vcf,
        hapmap_index = hapmap_vcf_index,
        omni = omni_vcf,
        omni_index = omni_vcf_index,
        onekg = onekg_vcf,
        onekg_index = onekg_vcf_index,
        dbsnp = dbsnp_vcf,
        dbsnp_index = dbsnp_vcf_index,
        mode = "SNP",
        output_prefix = "${cohort_name}.snps"
    }

    call ApplyVQSR as ApplySNPsVQSR {
      input:
        vcf = GatherVcfs.output_vcf,
        vcf_index = GatherVcfs.output_vcf_index,
        recal_file = RecalibrateSNPs.recal,
        recal_index = RecalibrateSNPs.recal_index,
        tranches_file = RecalibrateSNPs.tranches,
        mode = "SNP",
        output_name = "${cohort_name}.snps_recal.vcf.gz"
    }

    call VariantRecalibrator as RecalibrateIndels {
      input:
        vcf = ApplySNPsVQSR.output_vcf,
        vcf_index = ApplySNPsVQSR.output_vcf_index,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        mills = mills_vcf,
        mills_index = mills_vcf_index,
        dbsnp = dbsnp_vcf,
        dbsnp_index = dbsnp_vcf_index,
        mode = "INDEL",
        output_prefix = "${cohort_name}.indels"
    }

    call ApplyVQSR as ApplyIndelsVQSR {
      input:
        vcf = ApplySNPsVQSR.output_vcf,
        vcf_index = ApplySNPsVQSR.output_vcf_index,
        recal_file = RecalibrateIndels.recal,
        recal_index = RecalibrateIndels.recal_index,
        tranches_file = RecalibrateIndels.tranches,
        mode = "INDEL",
        output_name = "${cohort_name}.vqsr.vcf.gz"
    }
  }

  if (!use_vqsr) {
    call HardFilterVariants {
      input:
        vcf = GatherVcfs.output_vcf,
        vcf_index = GatherVcfs.output_vcf_index,
        output_name = "${cohort_name}.hard_filtered.vcf.gz"
    }
  }

  output {
    File joint_vcf = select_first([ApplyIndelsVQSR.output_vcf, HardFilterVariants.output_vcf])
    File joint_vcf_index = select_first([ApplyIndelsVQSR.output_vcf_index, HardFilterVariants.output_vcf_index])
  }
}

# ── TASKS ─────────────────────────────────────────────────

task CombineGVCFs {
  input {
    Array[File] gvcfs
    Array[File] gvcf_indices
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    String interval
    String output_name
  }

  command <<<
    gatk CombineGVCFs \
      --reference ~{ref_fasta} \
      ~{sep=' ' prefix('--variant ', gvcfs)} \
      --intervals ~{interval} \
      --output ~{output_name}
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "16 GB"
    cpu: 2
    disks: "local-disk 100 HDD"
  }

  output {
    File output_gvcf = output_name
    File output_gvcf_index = "${output_name}.tbi"
  }
}

task GenotypeGVCFs {
  input {
    File combined_gvcf
    File combined_gvcf_index
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File dbsnp_vcf
    File dbsnp_vcf_index
    String interval
    String output_name
  }

  command <<<
    gatk GenotypeGVCFs \
      --reference ~{ref_fasta} \
      --variant ~{combined_gvcf} \
      --dbsnp ~{dbsnp_vcf} \
      --intervals ~{interval} \
      --output ~{output_name}
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "16 GB"
    cpu: 2
    disks: "local-disk 100 HDD"
  }

  output {
    File output_vcf = output_name
    File output_vcf_index = "${output_name}.tbi"
  }
}

task GatherVcfs {
  input {
    Array[File] input_vcfs
    String output_name
  }

  command <<<
    gatk GatherVcfs \
      ~{sep=' ' prefix('--INPUT ', input_vcfs)} \
      --OUTPUT ~{output_name}
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "8 GB"
    cpu: 1
    disks: "local-disk 50 HDD"
  }

  output {
    File output_vcf = output_name
    File output_vcf_index = "${output_name}.tbi"
  }
}

task VariantRecalibrator {
  input {
    File vcf
    File vcf_index
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    String mode  # SNP or INDEL
    String output_prefix

    # SNP resources
    File? hapmap
    File? hapmap_index
    File? omni
    File? omni_index
    File? onekg
    File? onekg_index
    
    # INDEL resources
    File? mills
    File? mills_index
    
    # Common
    File? dbsnp
    File? dbsnp_index
  }

  command <<<
    gatk VariantRecalibrator \
      --reference ~{ref_fasta} \
      --variant ~{vcf} \
      --mode ~{mode} \
      ~{if mode == "SNP" then 
        "--resource:hapmap,known=false,training=true,truth=true,prior=15.0 " + hapmap + " " +
        "--resource:omni,known=false,training=true,truth=true,prior=12.0 " + omni + " " +
        "--resource:1000G,known=false,training=true,truth=false,prior=10.0 " + onekg + " " +
        "--resource:dbsnp,known=true,training=false,truth=false,prior=2.0 " + dbsnp + " " +
        "-an QD -an MQ -an MQRankSum -an ReadPosRankSum -an FS -an SOR"
        else 
        "--resource:mills,known=false,training=true,truth=true,prior=12.0 " + mills + " " +
        "--resource:dbsnp,known=true,training=false,truth=false,prior=2.0 " + dbsnp + " " +
        "-an QD -an MQRankSum -an ReadPosRankSum -an FS -an SOR"
      } \
      --tranches-file ~{output_prefix}.tranches \
      --output ~{output_prefix}.recal
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "24 GB"
    cpu: 2
    disks: "local-disk 100 HDD"
  }

  output {
    File recal = "${output_prefix}.recal"
    File recal_index = "${output_prefix}.recal.idx"
    File tranches = "${output_prefix}.tranches"
  }
}

task ApplyVQSR {
  input {
    File vcf
    File vcf_index
    File recal_file
    File recal_index
    File tranches_file
    String mode
    String output_name
  }

  command <<<
    gatk ApplyVQSR \
      --variant ~{vcf} \
      --recal-file ~{recal_file} \
      --tranches-file ~{tranches_file} \
      --mode ~{mode} \
      --truth-sensitivity-filter-level 99.0 \
      --output ~{output_name}
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "8 GB"
    cpu: 1
    disks: "local-disk 100 HDD"
  }

  output {
    File output_vcf = output_name
    File output_vcf_index = "${output_name}.tbi"
  }
}

task HardFilterVariants {
  input {
    File vcf
    File vcf_index
    String output_name
  }

  command <<<
    gatk VariantFiltration \
      --variant ~{vcf} \
      --filter-expression "QD < 2.0 || FS > 60.0 || MQ < 40.0 || MQRankSum < -12.5 || ReadPosRankSum < -8.0" \
      --filter-name "HARD_FILTER" \
      --output ~{output_name}
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.5.0.0"
    memory: "8 GB"
    cpu: 1
    disks: "local-disk 50 HDD"
  }

  output {
    File output_vcf = output_name
    File output_vcf_index = "${output_name}.tbi"
  }
}
