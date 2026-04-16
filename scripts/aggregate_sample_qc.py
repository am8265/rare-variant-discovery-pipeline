#!/usr/bin/env python3
"""
aggregate_sample_qc.py

Aggregate sample-level QC reports and create manifest for joint genotyping.
Only includes samples that passed QC filters.

Usage:
    python aggregate_sample_qc.py \
        --qc-dir s3://bucket/qc-reports/ \
        --output-manifest joint_genotyping_manifest.tsv \
        --output-report cohort_qc_summary.tsv
"""

import argparse
import pandas as pd
import boto3
from pathlib import Path


def download_qc_files(s3_prefix: str, local_dir: str):
    """Download all .qc_summary.tsv files from S3."""
    s3 = boto3.client("s3")
    parts = s3_prefix.replace("s3://", "").split("/", 1)
    bucket = parts[0]
    prefix = parts[1] if len(parts) > 1 else ""
    
    paginator = s3.get_paginator("list_objects_v2")
    local_path = Path(local_dir)
    local_path.mkdir(exist_ok=True)
    
    files = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        if "Contents" not in page:
            continue
        for obj in page["Contents"]:
            key = obj["Key"]
            if key.endswith(".qc_summary.tsv"):
                local_file = local_path / Path(key).name
                s3.download_file(bucket, key, str(local_file))
                files.append(local_file)
    
    return files


def aggregate_qc_reports(qc_files: list) -> pd.DataFrame:
    """Combine all sample QC reports into single DataFrame."""
    dfs = []
    for qc_file in qc_files:
        df = pd.read_csv(qc_file, sep="\t")
        dfs.append(df)
    
    return pd.concat(dfs, ignore_index=True)


def create_joint_genotyping_manifest(
    qc_df: pd.DataFrame,
    gvcf_s3_prefix: str,
    output_path: str
):
    """Create manifest of PASS samples for joint genotyping."""
    # Filter to PASS samples only
    passed = qc_df[qc_df["qc_status"] == True].copy()
    
    # Build S3 paths
    passed["gvcf"] = passed["sample_id"].apply(
        lambda x: f"{gvcf_s3_prefix}/{x}.g.vcf.gz"
    )
    passed["gvcf_index"] = passed["gvcf"] + ".tbi"
    
    # Write manifest
    manifest = passed[["sample_id", "gvcf", "gvcf_index"]]
    manifest.to_csv(output_path, sep="\t", index=False)
    
    print(f"✅ Wrote manifest with {len(manifest)} samples to {output_path}")
    return manifest


def print_qc_summary(qc_df: pd.DataFrame):
    """Print cohort-level QC summary statistics."""
    total = len(qc_df)
    passed = (qc_df["qc_status"] == True).sum()
    failed = total - passed
    
    print("\n" + "="*60)
    print("COHORT QC SUMMARY")
    print("="*60)
    print(f"Total samples:  {total}")
    print(f"Passed QC:      {passed} ({100*passed/total:.1f}%)")
    print(f"Failed QC:      {failed} ({100*failed/total:.1f}%)")
    print()
    
    # Coverage stats
    print(f"Mean coverage:  {qc_df['mean_coverage'].mean():.1f}x ± {qc_df['mean_coverage'].std():.1f}x")
    print(f"  Min: {qc_df['mean_coverage'].min():.1f}x")
    print(f"  Max: {qc_df['mean_coverage'].max():.1f}x")
    print()
    
    # Mapping rate
    print(f"Mapping rate:   {qc_df['mapping_rate'].mean():.2f}% ± {qc_df['mapping_rate'].std():.2f}%")
    print()
    
    # Ti/Tv
    print(f"Ti/Tv ratio:    {qc_df['tstv_ratio'].mean():.3f} ± {qc_df['tstv_ratio'].std():.3f}")
    print()
    
    # Failure reasons
    if failed > 0:
        print("Failure breakdown:")
        fail_df = qc_df[qc_df["qc_status"] == False]
        for reason in ["LOW_COVERAGE", "LOW_MAPPING_RATE", "ABNORMAL_TSTV"]:
            count = fail_df["fail_reasons"].str.contains(reason).sum()
            if count > 0:
                print(f"  {reason}: {count} samples")
    
    print("="*60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate sample QC and create joint genotyping manifest"
    )
    parser.add_argument(
        "--qc-dir",
        required=True,
        help="S3 prefix with QC reports"
    )
    parser.add_argument(
        "--gvcf-dir",
        required=True,
        help="S3 prefix with GVCFs"
    )
    parser.add_argument(
        "--output-manifest",
        default="joint_genotyping_manifest.tsv",
        help="Output manifest for joint genotyping"
    )
    parser.add_argument(
        "--output-report",
        default="cohort_qc_summary.tsv",
        help="Output QC summary report"
    )
    parser.add_argument(
        "--local-temp",
        default="./qc_temp",
        help="Local temp directory for downloads"
    )
    
    args = parser.parse_args()
    
    # Download QC files
    print(f"Downloading QC reports from {args.qc_dir}...")
    qc_files = download_qc_files(args.qc_dir, args.local_temp)
    print(f"Found {len(qc_files)} QC reports")
    
    # Aggregate
    print("Aggregating QC reports...")
    qc_df = aggregate_qc_reports(qc_files)
    
    # Print summary
    print_qc_summary(qc_df)
    
    # Create manifest
    print(f"Creating joint genotyping manifest...")
    manifest = create_joint_genotyping_manifest(
        qc_df,
        args.gvcf_dir,
        args.output_manifest
    )
    
    # Write full QC report
    qc_df.to_csv(args.output_report, sep="\t", index=False)
    print(f"✅ Wrote full QC report to {args.output_report}")


if __name__ == "__main__":
    main()
