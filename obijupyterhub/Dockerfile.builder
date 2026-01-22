# Dockerfile.builder
# Image containing all tools needed to prepare the OBIJupyterHub stack
# This allows the host system to only require Docker to be installed

FROM ubuntu:24.04

LABEL maintainer="OBIJupyterHub"
LABEL description="Builder image for OBIJupyterHub preparation tasks"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install base dependencies and R
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       wget \
       git \
       rsync \
       python3 \
       r-base \
       r-base-dev \
       libcurl4-openssl-dev \
       libssl-dev \
       libxml2-dev \
       libfontconfig1-dev \
       libharfbuzz-dev \
       libfribidi-dev \
       libfreetype6-dev \
       libpng-dev \
       libtiff5-dev \
       libjpeg-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install the attachment package in a separate location (not overwritten by volume mount)
# This ensures attachment is always available even when site-library is mounted as a volume
ENV R_LIBS_BUILDER=/opt/R/builder-packages
RUN mkdir -p ${R_LIBS_BUILDER} \
    && R -e "install.packages('attachment', lib='${R_LIBS_BUILDER}', repos='https://cloud.r-project.org/')"

# Install Hugo (extended version for SCSS support)
# Detect architecture and download appropriate binary
ARG HUGO_VERSION=0.140.2
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) HUGO_ARCH="amd64" ;; \
         arm64) HUGO_ARCH="arm64" ;; \
         *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-${HUGO_ARCH}.tar.gz" \
       | tar -xz -C /usr/local/bin hugo \
    && chmod +x /usr/local/bin/hugo

# Install Quarto using the official .deb package (handles all dependencies properly)
ARG QUARTO_VERSION=1.6.42
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL -o /tmp/quarto.deb "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${ARCH}.deb" \
    && dpkg -i /tmp/quarto.deb \
    && rm /tmp/quarto.deb

# Create working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
