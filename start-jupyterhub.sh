#!/bin/bash

# JupyterHub startup script for labs
# Usage: ./start-jupyterhub.sh [--no-build|--offline] [--force-rebuild] [--stop-server] [--update-lectures] [--build-obidoc]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="${SCRIPT_DIR}/obijupyterhub/"
BUILDER_IMAGE="obijupyterhub-builder:latest"

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
REBUILD_BUILDER=false
REBUILD_STUDENT=false
REBUILD_HUB=false

usage() {
    cat <<EOF
Usage: ./start-jupyterhub.sh [options]

Options:
  --no-build | --offline   Skip Docker image builds (use existing images)
  --force-rebuild          Rebuild all images without cache
  --rebuild-builder        Force rebuild the builder image only
  --rebuild-student        Force rebuild the student image only
  --rebuild-hub            Force rebuild the JupyterHub image only
  --stop-server            Stop the stack and remove student containers, then exit
  --update-lectures        Rebuild the course website only (no Docker stop/start)
  --build-obidoc           Force rebuild of obidoc documentation
  -h, --help               Show this help
EOF
}


dockercompose=$(which docker-compose || echo 'docker compose')


while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build|--offline) NO_BUILD=true ;;
        --force-rebuild) FORCE_REBUILD=true ;;
        --rebuild-builder) REBUILD_BUILDER=true ;;
        --rebuild-student) REBUILD_STUDENT=true ;;
        --rebuild-hub) REBUILD_HUB=true ;;
        --stop-server) STOP_SERVER=true ;;
        --update-lectures) UPDATE_LECTURES=true ;;
        --build-obidoc) BUILD_OBIDOC=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if $STOP_SERVER && $UPDATE_LECTURES; then
    echo "Error: --stop-server and --update-lectures cannot be used together" >&2
    exit 1
fi

echo "Starting JupyterHub for Lab"
echo "=============================="
echo ""

echo -e "${BLUE}Building the volume directories...${NC}"
pushd "${SCRIPT_DIR}/jupyterhub_volumes" >/dev/null
mkdir -p caddy/data
mkdir -p caddy/config
mkdir -p course/bin
mkdir -p course/R_packages
mkdir -p jupyterhub
mkdir -p shared
mkdir -p users
mkdir -p web/obidoc
mkdir -p builder/R_packages
popd >/dev/null

pushd "${DOCKER_DIR}" >/dev/null

# Check we're in the right directory
if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
    echo "Error: Run this script from the jupyterhub-tp/ directory"
    exit 1
fi

get_file_timestamp() {
    local file="$1"
    case "$(uname -s)" in
        Linux)
            stat -c %Y "$file"
            ;;
        Darwin)
            # BSD stat : -f pour format, %m = timestamp modification
            stat -f %m "$file"
            ;;
        *)
            echo "Système non supporté" >&2
            return 1
            ;;
    esac
}

check_if_image_needs_rebuild() {
    local image_name="$1"
    local dockerfile="$2"
    local force="${3:-false}"

    echo -e "${BLUE}Checking image ${image_name}...${NC}"

    # Check if image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker image ${image_name} doesn't exist.${NC}"
        return 0  # Need to build (image doesn't exist)
    fi

    # If force rebuild (global or per-image), always rebuild
    if $FORCE_REBUILD || $force; then
        echo -e "${YELLOW}Docker image build is forced.${NC}"
        return 0  # Need to rebuild
    fi

    # Compare Dockerfile modification time with image creation time
    if [ -f "$dockerfile" ]; then
        local dockerfile_mtime=$(get_file_timestamp "$dockerfile" 2>/dev/null || echo 0)
        local image_created=$(docker image inspect "$image_name" --format='{{.Created}}' 2>/dev/null \
              | sed -E 's/\.[0-9]+//' \
              | (read d; if [[ "$(uname -s)" == "Darwin" ]]; then date -ju -f "%Y-%m-%dT%H:%M:%S" "${d%Z}" +%s; else date -d "$d" +%s; fi) 2>/dev/null || echo 0)

        echo -e "${BLUE}Docker image ${image_name} created at: ${image_created}.${NC}"
        echo -e "${BLUE}Docker file ${dockerfile} modified at: ${dockerfile_mtime}.${NC}"

        if [ "$dockerfile_mtime" -gt "$image_created" ]; then
            echo -e "${YELLOW}Dockerfile is newer than image, rebuild needed${NC}"
            return 0  # Need to rebuild
        fi
    fi

    return 1  # No need to rebuild
}

build_builder_image() {
    if check_if_image_needs_rebuild "$BUILDER_IMAGE" "Dockerfile.builder" "$REBUILD_BUILDER"; then
        local build_flag=()
        if $FORCE_REBUILD || $REBUILD_BUILDER; then
            build_flag+=(--no-cache)
        fi

        echo ""
        echo -e "${BLUE}Building builder image...${NC}"
        docker build "${build_flag[@]}" -t "$BUILDER_IMAGE" -f Dockerfile.builder .
    else
        echo -e "${BLUE}Builder image is up to date, skipping build.${NC}"
    fi
}

# Run a command inside the builder container with the workspace mounted
# R packages are persisted in jupyterhub_volumes/builder/R_packages
# R_LIBS includes both the builder packages (attachment) and the mounted volume
run_in_builder() {
    docker run --rm \
        -v "${SCRIPT_DIR}:/workspace" \
        -v "${SCRIPT_DIR}/jupyterhub_volumes/builder/R_packages:/usr/local/lib/R/site-library" \
        -e "R_LIBS=/opt/R/builder-packages:/usr/local/lib/R/site-library" \
        -w /workspace \
        "$BUILDER_IMAGE" \
        bash -c "$1"
}

stop_stack() {
    echo -e "${BLUE}Stopping existing containers...${NC}"
    ${dockercompose} down 2>/dev/null || true

    echo -e "${BLUE}Cleaning up student containers...${NC}"
    docker ps -aq --filter name=jupyter- | xargs -r docker rm -f 2>/dev/null || true
}

build_images() {
    if $NO_BUILD; then
        echo -e "${YELLOW}Skipping image builds (offline/no-build mode).${NC}"
        return
    fi

    # Check and build student image
    if check_if_image_needs_rebuild "jupyterhub-student:latest" "Dockerfile" "$REBUILD_STUDENT"; then
        local student_flag=()
        if $FORCE_REBUILD || $REBUILD_STUDENT; then
            student_flag+=(--no-cache)
        fi
        echo ""
        echo -e "${BLUE}Building student image...${NC}"
        docker build "${student_flag[@]}" -t jupyterhub-student:latest -f Dockerfile .
    else
        echo -e "${BLUE}Student image is up to date, skipping build.${NC}"
    fi

    # Check and build JupyterHub image
    if check_if_image_needs_rebuild "jupyterhub-hub:latest" "Dockerfile.hub" "$REBUILD_HUB"; then
        local hub_flag=()
        if $FORCE_REBUILD || $REBUILD_HUB; then
            hub_flag+=(--no-cache)
        fi
        echo ""
        echo -e "${BLUE}Building JupyterHub image...${NC}"
        docker build "${hub_flag[@]}" -t jupyterhub-hub:latest -f Dockerfile.hub .
    else
        echo -e "${BLUE}JupyterHub image is up to date, skipping build.${NC}"
    fi
}

build_obidoc() {
    local dest="${SCRIPT_DIR}/jupyterhub_volumes/web/obidoc"

    if $NO_BUILD; then
        echo -e "${YELLOW}Skipping obidoc build in offline/no-build mode.${NC}"
        return
    fi

    local needs_build=false
    if $BUILD_OBIDOC; then
        needs_build=true
    elif [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        needs_build=true
    fi

    if ! $needs_build; then
        echo -e "${BLUE}obidoc already present; skipping rebuild (use --build-obidoc to force).${NC}"
        return
    fi

    echo ""
    echo -e "${BLUE}Building obidoc documentation (in builder container)...${NC}"
    run_in_builder '
        set -e
        BUILD_DIR=$(mktemp -d)
        cd "$BUILD_DIR"
        git clone --recurse-submodules \
              --remote-submodules \
              -j 8 \
              https://github.com/metabarcoding/obitools4-doc.git
        cd obitools4-doc
        hugo -D build --baseURL "/obidoc/"
        mkdir -p /workspace/jupyterhub_volumes/web/obidoc
        rm -rf /workspace/jupyterhub_volumes/web/obidoc/*
        mv public/* /workspace/jupyterhub_volumes/web/obidoc/
        cd /
        rm -rf "$BUILD_DIR"
    '
}

build_website() {
    echo ""
    echo -e "${BLUE}Building web site (in builder container)...${NC}"
    run_in_builder '
        set -e
        echo "-> Detecting and installing R dependencies..."
        Rscript /workspace/tools/install_quarto_deps.R /workspace/web_src

        echo "-> Rendering Quarto site..."
        cd /workspace/web_src
        quarto render
        find . -name "*.pdf" -print | while read pdfname; do
            dest="/workspace/jupyterhub_volumes/web/pages/${pdfname}"
            dirdest=$(dirname "$dest")
            mkdir -p "$dirdest"
            cp "$pdfname" "$dest"
        done
        python3 /workspace/tools/generate_pdf_galleries.py
        python3 /workspace/tools/generate_pages_json.py
    '
}

start_stack() {
    echo ""
    echo -e "${BLUE}Starting JupyterHub...${NC}"
    ${dockercompose} up -d --remove-orphans

    echo ""
    echo -e "${YELLOW}Waiting for JupyterHub to start...${NC}"
    sleep 3
}

print_success() {
    if docker ps | grep -q jupyterhub; then
        echo ""
        echo -e "${GREEN}JupyterHub is running!${NC}"
        echo ""
        echo "-------------------------------------------"
        echo -e "${GREEN}JupyterHub available at: http://localhost:8888${NC}"
        echo "-------------------------------------------"
        echo ""
        echo "Password: metabar2025"
        echo "Students can connect with any username"
        echo ""
        echo "Admin account:"
        echo "   Username: admin"
        echo "   Password: admin2025"
        echo ""
        echo "Each student will have access to:"
        echo "   - work/                     : personal workspace (everything saved)"
        echo "   - work/R_packages/          : personal R packages (writable)"
        echo "   - work/shared/              : shared workspace"
        echo "   - work/course/              : course files (read-only)"
        echo "   - work/course/R_packages/   : shared R packages by prof (read-only)"
        echo "   - work/course/bin/          : shared executables (in PATH)"
        echo ""
        echo "To view logs:    ${dockercompose} logs -f jupyterhub"
        echo "To stop:         ${dockercompose} down"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}JupyterHub container doesn't seem to be starting${NC}"
        echo "Check logs with: ${dockercompose} logs jupyterhub"
        exit 1
    fi
}

if $STOP_SERVER; then
    stop_stack
    popd >/dev/null
    exit 0
fi

if $UPDATE_LECTURES; then
    build_builder_image
    build_website
    popd >/dev/null
    exit 0
fi

stop_stack
build_builder_image
build_images
build_website
build_obidoc
start_stack

popd >/dev/null
print_success
