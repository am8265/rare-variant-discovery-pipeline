#!/usr/bin/env python3
"""
generate_manifest.py

Generate TSV manifest file for cohort processing workflows.
Scans S3 bucket for per-sample GVCFs and creates input manifest.

Usage:
    python generate_manifest.py \
        --s3-prefix s3://chop-genomics/single-sample-vcfs/ \
        --output cohort_manifest.tsv
"""

import argparse
import boto3
import sys
from pathlib import Path


def scan_s3_gvcfs(s3_prefix: str) -> list[dict]:
    """
    Scan S3 prefix for GVCF files and return metadata.
    
    Args:
        s3_prefix: S3 URI (e.g., s3://bucket/path/)
    
    Returns:
        List of dicts with sample_id, gvcf_path, gvcf_index_path
    """
    # Parse S3 URI
    if not s3_prefix.startswith("s3://"):
        raise ValueError("S3 prefix must start with s3://")
    
    parts = s3_prefix.replace("s3://", "").split("/", 1)
    bucket = parts[0]
    prefix = parts[1] if len(parts) > 1 else ""
    
    s3 = boto3.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    
    gvcfs = []
    
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        if "Contents" not in page:
            continue
        
        for obj in page["Contents"]:
            key = obj["Key"]
            
            # Match .g.vcf.gz files (not indices)
            if key.endswith(".g.vcf.gz") and not key.endswith(".tbi"):
                sample_id = Path(key).stem.replace(".g.vcf", "")
                gvcf_uri = f"s3://{bucket}/{key}"
                index_uri = f"{gvcf_uri}.tbi"
                
                gvcfs.append({
                    "sample_id": sample_id,
                    "gvcf": gvcf_uri,
                    "gvcf_index": index_uri
                })
    
    return gvcfs


def write_manifest(gvcfs: list[dict], output_path: str):
    """Write manifest TSV file."""
    with open(output_path, "w") as f:
        # Header
        f.write("sample_id\tgvcf\tgvcf_index\n")
        
        # Rows
        for entry in sorted(gvcfs, key=lambda x: x["sample_id"]):
            f.write(f"{entry['sample_id']}\t{entry['gvcf']}\t{entry['gvcf_index']}\n")
    
    print(f"✅ Wrote manifest with {len(gvcfs)} samples to {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate cohort manifest from S3 GVCF files"
    )
    parser.add_argument(
        "--s3-prefix",
        required=True,
        help="S3 URI prefix to scan (e.g., s3://bucket/path/)"
    )
    parser.add_argument(
        "--output",
        default="cohort_manifest.tsv",
        help="Output manifest TSV file"
    )
    parser.add_argument(
        "--min-samples",
        type=int,
        default=1,
        help="Minimum number of samples required"
    )
    
    args = parser.parse_args()
    
    print(f"Scanning {args.s3_prefix} for GVCFs...")
    gvcfs = scan_s3_gvcfs(args.s3_prefix)
    
    if len(gvcfs) < args.min_samples:
        print(f"❌ Found only {len(gvcfs)} samples, need at least {args.min_samples}")
        sys.exit(1)
    
    print(f"Found {len(gvcfs)} GVCF files")
    write_manifest(gvcfs, args.output)


if __name__ == "__main__":
    main()
