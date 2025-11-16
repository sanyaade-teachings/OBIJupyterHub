#!/bin/bash

# JupyterHub startup script for labs
# Usage: ./start-jupyterhub.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="${SCRIPT_DIR}/obijupyterhub/"

set -e  # Stop on error

echo "🚀 Starting JupyterHub for Lab"
echo "=============================="
echo ""

# Compile the web site
echo ""
echo  -e "${BLUE}🔨 Building the volume directories...${NC}"
pushd "${SCRIPT_DIR}/jupyterhub_volumes"
mkdir -p caddy
mkdir -p course/bin
mkdir -p course/R_packages
mkdir -p jupyterhub
mkdir -p shared
mkdir -p users
popd

# Colors for display
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pushd "${DOCKER_DIR}"

# Check we're in the right directory
if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: Run this script from the jupyterhub-tp/ directory"
    exit 1
fi

# Stop existing containers
echo -e "${BLUE}📦 Stopping existing containers...${NC}"
docker-compose down 2>/dev/null || true

# Remove old student containers
echo -e "${BLUE}🧹 Cleaning up student containers...${NC}"
docker ps -aq --filter name=jupyter- | xargs -r docker rm -f 2>/dev/null || true

# Build student image
echo ""
echo -e "${BLUE}🔨 Building student image...${NC}"
docker build -t jupyterhub-student:latest -f Dockerfile .

# Build hub image
echo ""
echo -e "${BLUE}🔨 Building JupyterHub image...${NC}"
docker build -t jupyterhub-hub:latest -f Dockerfile.hub .

# Compile the web site
echo ""
echo  -e "${BLUE}🔨 Building web site...${NC}"
pushd ../web_src
quarto render
find . -name '*.pdf' -print \
| while read pdfname ; do 
    dest="../jupyterhub_volumes/web/pages/${pdfname}"
	dirdest=$(dirname "$dest")
	mkdir -p "$dirdest"
    echo "cp '${pdfname}' '${dest}'"  
  done \
| bash
python3 ../tools/generate_pdf_galleries.py
python3 ../tools/generate_pages_json.py
popd

# Start the stack
echo ""
echo -e "${BLUE}🚀 Starting JupyterHub...${NC}"
docker-compose up -d --remove-orphans

# Wait for service to be ready
echo ""
echo -e "${YELLOW}⏳ Waiting for JupyterHub to start...${NC}"
sleep 3

popd

# Check that container is running
if docker ps | grep -q jupyterhub; then
    echo ""
    echo -e "${GREEN}✅ JupyterHub is running!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🌐 JupyterHub available at: http://localhost:8888${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📝 Password: metabar2025"
    echo "👥 Students can connect with any username"
    echo ""
    echo "🔑 Admin account:"
    echo "   Username: admin"
    echo "   Password: admin2025"
    echo ""
    echo "📂 Each student will have access to:"
    echo "   - work/                     : personal workspace (everything saved)"
    echo "   - work/R_packages/          : personal R packages (writable)"
    echo "   - work/shared/              : shared workspace"
    echo "   - work/course/              : course files (read-only)"
    echo "   - work/course/R_packages/   : shared R packages by prof (read-only)"
    echo "   - work/course/bin/          : shared executables (in PATH)"
    echo ""
    echo "🔍 To view logs:    docker-compose logs -f jupyterhub"
    echo "🛑 To stop:         docker-compose down"
    echo ""
else
    echo ""
    echo -e "${YELLOW}⚠️  JupyterHub container doesn't seem to be starting${NC}"
    echo "Check logs with: docker-compose logs jupyterhub"
    exit 1
fi
