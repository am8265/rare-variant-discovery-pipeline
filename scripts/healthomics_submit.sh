#!/bin/bash
# healthomics_submit.sh
# AWS HealthOmics workflow submission examples
# Demonstrates real commands used to run WDL workflows on HealthOmics

set -euo pipefail

# ─────────────────────────────────────────────────────────
# 1. Create a workflow from WDL
# ─────────────────────────────────────────────────────────

create_vt_workflow() {
  aws omics create-workflow \
    --name "vt-normalization" \
    --description "VT decompose + normalize for cohort VCF" \
    --engine WDL \
    --definition-zip fileb://vt-normalization.zip \
    --parameter-template file://vt-normalization-params.json \
    --storage-capacity 1200 \
    --tags Project=RareVariantPipeline,Pipeline=VTNormalization
}

# ─────────────────────────────────────────────────────────
# 2. Start a workflow run
# ─────────────────────────────────────────────────────────

run_vt_normalization() {
  local WORKFLOW_ID="1234567"  # from create-workflow output
  local INPUT_VCF="s3://chop-genomics/joint-vcfs/cohort.joint.vcf.gz"
  local OUTPUT_PREFIX="cohort.normalized"
  
  aws omics start-run \
    --workflow-id "$WORKFLOW_ID" \
    --role-arn "arn:aws:iam::123456789012:role/HealthOmicsWorkflowRole" \
    --name "vt-normalize-cohort-run-$(date +%Y%m%d)" \
    --parameters '{
      "VTNormalize.input_vcf": "'"$INPUT_VCF"'",
      "VTNormalize.output_prefix": "'"$OUTPUT_PREFIX"'",
      "VTNormalize.ref_fasta": "s3://broad-references/hg38/v0/Homo_sapiens_assembly38.fasta"
    }' \
    --output-uri "s3://chop-genomics/healthomics-outputs/vt-normalization/" \
    --storage-capacity 1200 \
    --log-level ALL \
    --tags RunDate=$(date +%Y%m%d),Cohort=production
}

# ─────────────────────────────────────────────────────────
# 3. Monitor workflow run status
# ─────────────────────────────────────────────────────────

check_run_status() {
  local RUN_ID="$1"
  
  aws omics get-run \
    --id "$RUN_ID" \
    --query '{
      status: status,
      startTime: startTime,
      runningTime: runningTime,
      outputUri: outputUri,
      failureReason: statusMessage
    }' \
    --output table
}

# Poll until completion
wait_for_run() {
  local RUN_ID="$1"
  
  while true; do
    STATUS=$(aws omics get-run --id "$RUN_ID" --query 'status' --output text)
    
    case "$STATUS" in
      COMPLETED)
        echo "✅ Run completed successfully"
        break
        ;;
      FAILED|CANCELLED)
        echo "❌ Run failed or cancelled"
        aws omics get-run --id "$RUN_ID" --query 'statusMessage' --output text
        exit 1
        ;;
      *)
        echo "⏳ Status: $STATUS ... waiting 30s"
        sleep 30
        ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────
# 4. List workflow runs
# ─────────────────────────────────────────────────────────

list_recent_runs() {
  aws omics list-runs \
    --max-results 10 \
    --query 'items[].{
      id: id,
      name: name,
      status: status,
      startTime: startTime
    }' \
    --output table
}

# ─────────────────────────────────────────────────────────
# 5. VEP annotation workflow submission
# ─────────────────────────────────────────────────────────

run_vep_annotation() {
  local WORKFLOW_ID="7654321"  # VEP workflow ID
  local INPUT_VCF="s3://chop-genomics/rare-variants/rare_variants_sites_only.vcf.gz"
  local VEP_CACHE="s3://chop-genomics/references/vep_cache_110.tar.gz"
  
  aws omics start-run \
    --workflow-id "$WORKFLOW_ID" \
    --role-arn "arn:aws:iam::123456789012:role/HealthOmicsWorkflowRole" \
    --name "vep-annotate-rare-variants-$(date +%Y%m%d)" \
    --parameters '{
      "VEPAnnotation.input_vcf": "'"$INPUT_VCF"'",
      "VEPAnnotation.vep_cache_tar_gz": "'"$VEP_CACHE"'",
      "VEPAnnotation.genome_assembly": "GRCh38",
      "VEPAnnotation.output_prefix": "rare_variants_vep"
    }' \
    --output-uri "s3://chop-genomics/healthomics-outputs/vep-annotation/" \
    --storage-capacity 2000 \
    --log-level ALL
}

# ─────────────────────────────────────────────────────────
# 6. Get task-level logs
# ─────────────────────────────────────────────────────────

get_task_logs() {
  local RUN_ID="$1"
  local TASK_ID="$2"
  
  aws omics get-run-task \
    --id "$RUN_ID" \
    --task-id "$TASK_ID" \
    --query '{
      status: status,
      logStream: logStream,
      cpus: cpus,
      memory: memory,
      startTime: startTime,
      stopTime: stopTime
    }' \
    --output table
}

# ─────────────────────────────────────────────────────────
# Example usage
# ─────────────────────────────────────────────────────────

# Create workflow (one-time setup)
# create_vt_workflow

# Submit a run
RUN_ID=$(run_vt_normalization | jq -r '.id')
echo "Started run: $RUN_ID"

# Monitor
wait_for_run "$RUN_ID"

# Check outputs
aws s3 ls "s3://chop-genomics/healthomics-outputs/vt-normalization/$RUN_ID/"
