#!/bin/bash

# Script to install R packages in the course directory (admin only)
# Usage: ./install-r-packages.sh package1 package2 package3

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}📦 R Package Installer (Admin)${NC}"
echo "================================"
echo ""

# Check if packages are provided
if [ $# -eq 0 ]; then
    echo -e "${RED}❌ Error: No packages specified${NC}"
    echo ""
    echo "Usage:"
    echo "  ./install-r-packages.sh package1 package2 package3"
    echo ""
    echo "Example:"
    echo "  ./install-r-packages.sh reshape2 plotly knitr"
    exit 1
fi

# Build package list
PACKAGES=$(IFS=,; echo "$*")
R_PACKAGES=$(echo "$PACKAGES" | sed "s/,/', '/g")

echo -e "${YELLOW}📋 Packages to install: ${R_PACKAGES}${NC}"
echo ""

# Create a temporary directory for installation
TEMP_DIR=$(mktemp -d)
echo -e "${BLUE}📁 Creating temporary directory: ${TEMP_DIR}${NC}"

# Install packages in temporary directory
echo -e "${BLUE}🔨 Installing R packages...${NC}"
docker run --rm \
    --user root \
    -v "${TEMP_DIR}:/temp_packages" \
    jupyterhub-student:latest \
    R -e "install.packages(c('${R_PACKAGES}'), lib='/temp_packages', repos='http://cran.rstudio.com/')" || {
    echo -e "${RED}❌ Failed to install packages${NC}"
    rm -rf "${TEMP_DIR}"
    exit 1
}

# Copy to course R packages directory
echo ""
echo -e "${BLUE}💾 Copying to course/R_packages...${NC}"
docker run --rm \
    -v jupyterhub-course:/target \
    -v "${TEMP_DIR}:/source" \
    alpine sh -c "mkdir -p /target/R_packages && cp -r /source/* /target/R_packages/"

# Clean up
rm -rf "${TEMP_DIR}"

# List installed packages
echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${BLUE}📦 Installed packages in work/course/R_packages:${NC}"
docker run --rm \
    -v jupyterhub-course:/course \
    alpine ls -1 /course/R_packages/

echo ""
echo -e "${YELLOW}ℹ️  Students need to restart their R kernels to use new packages.${NC}"
