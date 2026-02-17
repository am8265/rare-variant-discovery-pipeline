# ============================================================
# VT Normalization Docker Image
# ============================================================
# Tools:
#   - vt         0.57721  (decompose + normalize)
#   - bcftools   1.17     (stats + validation)
#   - htslib     1.17     (bgzip + tabix)
#   - python3    3.11     (utility scripts)
#
# Base: Ubuntu 22.04 LTS
# Size: ~350 MB
# ============================================================

FROM ubuntu:22.04

LABEL maintainer="Ayan Malakar <mailme.ayan@gmail.com>"
LABEL description="VT normalization pipeline: vt + bcftools + htslib"
LABEL version="1.0.0"

# ── Build args ────────────────────────────────────────────────
ARG DEBIAN_FRONTEND=noninteractive
ARG VT_VERSION=0.57721
ARG HTSLIB_VERSION=1.17
ARG BCFTOOLS_VERSION=1.17

# ── System dependencies ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ca-certificates \
    # Compression
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    # SSL + network
    libssl-dev \
    libcurl4-openssl-dev \
    # Utilities
    tabix \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ── Install htslib (provides bgzip + tabix) ──────────────────
RUN wget -q "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2" \
    && tar -xjf htslib-${HTSLIB_VERSION}.tar.bz2 \
    && cd htslib-${HTSLIB_VERSION} \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf htslib-${HTSLIB_VERSION} htslib-${HTSLIB_VERSION}.tar.bz2

# ── Install bcftools ──────────────────────────────────────────
RUN wget -q "https://github.com/samtools/bcftools/releases/download/${BCFTOOLS_VERSION}/bcftools-${BCFTOOLS_VERSION}.tar.bz2" \
    && tar -xjf bcftools-${BCFTOOLS_VERSION}.tar.bz2 \
    && cd bcftools-${BCFTOOLS_VERSION} \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf bcftools-${BCFTOOLS_VERSION} bcftools-${BCFTOOLS_VERSION}.tar.bz2

# ── Install vt ────────────────────────────────────────────────
# Build from source for reproducibility
RUN git clone https://github.com/atks/vt.git /opt/vt \
    && cd /opt/vt \
    && git checkout ${VT_VERSION} \
    && make -j$(nproc) \
    && cp vt /usr/local/bin/vt \
    && rm -rf /opt/vt

# ── Python utilities ──────────────────────────────────────────
RUN pip3 install --no-cache-dir \
    pandas==2.0.3 \
    cyvcf2==0.30.22

# ── Copy pipeline scripts ─────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.py 2>/dev/null || true

# ── Verify installations ──────────────────────────────────────
RUN echo "=== Tool Versions ===" \
    && vt 2>&1 | head -2 \
    && bcftools --version | head -1 \
    && bgzip --version | head -1 \
    && tabix --version | head -1 \
    && python3 --version \
    && echo "=== All tools verified ==="

# ── Set working directory ─────────────────────────────────────
WORKDIR /data

# ── Default command ───────────────────────────────────────────
CMD ["/bin/bash"]
