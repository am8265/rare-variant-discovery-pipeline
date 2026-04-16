#!/bin/bash
# post_dragen_qc.sh
# Sample-level QC after DRAGEN variant calling
# Run before joint genotyping to filter low-quality samples

set -euo pipefail

SAMPLE_ID="$1"
GVCF="$2"
BAM="$3"
OUTPUT_DIR="$4"

# ─────────────────────────────────────────────────────────
# 1. Extract basic stats from GVCF
# ─────────────────────────────────────────────────────────

echo "Extracting GVCF stats for ${SAMPLE_ID}..."

bcftools stats "${GVCF}" > "${OUTPUT_DIR}/${SAMPLE_ID}.gvcf.stats.txt"

# Parse key metrics
N_VARIANTS=$(grep "number of records:" "${OUTPUT_DIR}/${SAMPLE_ID}.gvcf.stats.txt" | awk '{print $NF}')
TSTV_RATIO=$(grep "TSTV" "${OUTPUT_DIR}/${SAMPLE_ID}.gvcf.stats.txt" | awk '{print $5}')

echo "  Variants: ${N_VARIANTS}"
echo "  Ti/Tv: ${TSTV_RATIO}"

# ─────────────────────────────────────────────────────────
# 2. BAM-level QC with samtools
# ─────────────────────────────────────────────────────────

echo "Running BAM QC for ${SAMPLE_ID}..."

samtools flagstat "${BAM}" > "${OUTPUT_DIR}/${SAMPLE_ID}.flagstat.txt"
samtools stats "${BAM}" > "${OUTPUT_DIR}/${SAMPLE_ID}.bam.stats.txt"

# Extract coverage
samtools depth "${BAM}" | awk '{sum+=$3; count++} END {print sum/count}' \
  > "${OUTPUT_DIR}/${SAMPLE_ID}.mean_coverage.txt"

MEAN_COV=$(cat "${OUTPUT_DIR}/${SAMPLE_ID}.mean_coverage.txt")
MAPPING_RATE=$(grep "mapped (" "${OUTPUT_DIR}/${SAMPLE_ID}.flagstat.txt" | head -1 | awk '{print $5}' | tr -d '(')

echo "  Mean coverage: ${MEAN_COV}x"
echo "  Mapping rate: ${MAPPING_RATE}"

# ─────────────────────────────────────────────────────────
# 3. Sample-level filters (PASS/FAIL decision)
# ─────────────────────────────────────────────────────────

PASS="true"
FAIL_REASONS=""

# Coverage threshold: WGS >= 30x, WES >= 100x
MIN_COVERAGE=30  # adjust for WES
if (( $(echo "${MEAN_COV} < ${MIN_COVERAGE}" | bc -l) )); then
  PASS="false"
  FAIL_REASONS="${FAIL_REASONS}LOW_COVERAGE(${MEAN_COV}x < ${MIN_COVERAGE}x); "
fi

# Mapping rate threshold: >= 95%
MIN_MAPPING_RATE=95.0
if (( $(echo "${MAPPING_RATE} < ${MIN_MAPPING_RATE}" | bc -l) )); then
  PASS="false"
  FAIL_REASONS="${FAIL_REASONS}LOW_MAPPING_RATE(${MAPPING_RATE}% < ${MIN_MAPPING_RATE}%); "
fi

# Ti/Tv ratio threshold: WGS ~2.0-2.3, WES ~3.0-3.5
MIN_TSTV=1.8
MAX_TSTV=2.5
if (( $(echo "${TSTV_RATIO} < ${MIN_TSTV}" | bc -l) )) || (( $(echo "${TSTV_RATIO} > ${MAX_TSTV}" | bc -l) )); then
  PASS="false"
  FAIL_REASONS="${FAIL_REASONS}ABNORMAL_TSTV(${TSTV_RATIO}, expected ${MIN_TSTV}-${MAX_TSTV}); "
fi

# ─────────────────────────────────────────────────────────
# 4. Write QC summary
# ─────────────────────────────────────────────────────────

cat > "${OUTPUT_DIR}/${SAMPLE_ID}.qc_summary.tsv" <<EOF
sample_id	mean_coverage	mapping_rate	tstv_ratio	n_variants	qc_status	fail_reasons
${SAMPLE_ID}	${MEAN_COV}	${MAPPING_RATE}	${TSTV_RATIO}	${N_VARIANTS}	${PASS}	${FAIL_REASONS}
EOF

if [[ "${PASS}" == "true" ]]; then
  echo "✅ ${SAMPLE_ID} PASSED QC"
  exit 0
else
  echo "❌ ${SAMPLE_ID} FAILED QC: ${FAIL_REASONS}"
  exit 1
fi
