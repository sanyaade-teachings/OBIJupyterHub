#!/bin/bash

# JupyterHub startup script for labs
# Usage: ./start-jupyterhub.sh [--no-build|--offline] [--force-rebuild] [--stop-server] [--update-lectures] [--build-obidoc]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="${SCRIPT_DIR}/obijupyterhub/"

# Colors for display
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NO_BUILD=false
FORCE_REBUILD=false
STOP_SERVER=false
UPDATE_LECTURES=false
BUILD_OBIDOC=false

usage() {
    cat <<EOF
Usage: ./start-jupyterhub.sh [options]

Options:
  --no-build | --offline   Skip Docker image builds (use existing images)
  --force-rebuild          Rebuild images without cache
  --stop-server            Stop the stack and remove student containers, then exit
  --update-lectures        Rebuild the course website only (no Docker stop/start)
  --build-obidoc           Force rebuild of obidoc documentation
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build|--offline) NO_BUILD=true ;;
        --force-rebuild) FORCE_REBUILD=true ;;
        --stop-server) STOP_SERVER=true ;;
        --update-lectures) UPDATE_LECTURES=true ;;
        --build-obidoc) BUILD_OBIDOC=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if $STOP_SERVER && $UPDATE_LECTURES; then
    echo "❌ --stop-server and --update-lectures cannot be used together" >&2
    exit 1
fi

echo "🚀 Starting JupyterHub for Lab"
echo "=============================="
echo ""

echo -e "${BLUE}🔨 Building the volume directories...${NC}"
pushd "${SCRIPT_DIR}/jupyterhub_volumes" >/dev/null
mkdir -p caddy
mkdir -p course/bin
mkdir -p course/R_packages
mkdir -p jupyterhub
mkdir -p shared
mkdir -p users
mkdir -p web/obidoc
popd >/dev/null

pushd "${DOCKER_DIR}" >/dev/null

# Check we're in the right directory
if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: Run this script from the jupyterhub-tp/ directory"
    exit 1
fi

stop_stack() {
    echo -e "${BLUE}📦 Stopping existing containers...${NC}"
    docker-compose down 2>/dev/null || true

    echo -e "${BLUE}🧹 Cleaning up student containers...${NC}"
    docker ps -aq --filter name=jupyter- | xargs -r docker rm -f 2>/dev/null || true
}

build_images() {
    if $NO_BUILD; then
        echo -e "${YELLOW}⏭️  Skipping image builds (offline/no-build mode).${NC}"
        return
    fi

    local build_flag=()
    if $FORCE_REBUILD; then
        build_flag+=(--no-cache)
    fi

    echo ""
    echo -e "${BLUE}🔨 Building student image...${NC}"
    docker build "${build_flag[@]}" -t jupyterhub-student:latest -f Dockerfile .

    echo ""
    echo -e "${BLUE}🔨 Building JupyterHub image...${NC}"
    docker build "${build_flag[@]}" -t jupyterhub-hub:latest -f Dockerfile.hub .
}

build_obidoc() {
    local dest="${SCRIPT_DIR}/jupyterhub_volumes/web/obidoc"

    if $NO_BUILD; then
        echo -e "${YELLOW}⏭️  Skipping obidoc build in offline/no-build mode.${NC}"
        return
    fi

    local needs_build=false
    if $BUILD_OBIDOC; then
        needs_build=true
    elif [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        needs_build=true
    fi

    if ! $needs_build; then
        echo -e "${BLUE}ℹ️  obidoc already present; skipping rebuild (use --build-obidoc to force).${NC}"
        return
    fi

    echo ""
    echo -e "${BLUE}🔨 Building obidoc documentation...${NC}"
    BUILD_DIR=$(mktemp -d -p .)
    pushd "$BUILD_DIR" >/dev/null
    git clone --recurse-submodules \
          --remote-submodules  \
          -j 8  \
          https://github.com/metabarcoding/obitools4-doc.git
	pushd obitools4-doc >/dev/null
    hugo -D build --baseURL "/obidoc/"
    mkdir -p "$dest"
    rm -rf "${dest:?}/"*
    mv public/* "$dest"
    popd >/dev/null
    popd >/dev/null
	rm -rf 
}

build_website() {
    echo ""
    echo  -e "${BLUE}🔨 Building web site...${NC}"
    pushd ../web_src >/dev/null
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
    popd >/dev/null
}

start_stack() {
    echo ""
    echo -e "${BLUE}🚀 Starting JupyterHub...${NC}"
    docker-compose up -d --remove-orphans

    echo ""
    echo -e "${YELLOW}⏳ Waiting for JupyterHub to start...${NC}"
    sleep 3
}

print_success() {
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
}

if $STOP_SERVER; then
    stop_stack
    popd >/dev/null
    exit 0
fi

if $UPDATE_LECTURES; then
    build_website
    popd >/dev/null
    exit 0
fi

stop_stack
build_images
build_website
build_obidoc
start_stack

popd >/dev/null
print_success
