#!/bin/bash

# JupyterHub startup script for labs
#
# Modes (mutually exclusive):
#   (default)      Pull images from registry and start
#   --local-build  Build images locally and start (no push)
#   --publish      Build multi-arch images, push to registry, and start
#
# Usage: ./start-jupyterhub.sh [mode] [options]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="${SCRIPT_DIR}/obijupyterhub/"

REGISTRY="registry.metabarcoding.org/metabarschool"
PLATFORMS="linux/amd64,linux/arm64"
BUILDX_BUILDER_NAME="obijupyterhub-buildx"

# Colors for display
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Operating mode
LOCAL_BUILD=false
PUBLISH=false

# Build options (meaningful in --local-build mode)
NO_BUILD=false
FORCE_REBUILD=false
REBUILD_BUILDER=false
REBUILD_STUDENT=false
REBUILD_HUB=false

# Actions
STOP_SERVER=false
UPDATE_LECTURES=false
BUILD_OBIDOC=false

usage() {
    cat <<EOF
Usage: ./start-jupyterhub.sh [mode] [options]

Modes (mutually exclusive, default is pull-from-registry):
  --local-build        Build images locally and start (no push to registry)
  --publish            Build multi-arch images, push to registry, and start

Build options (--local-build only):
  --no-build | --offline   Skip all image operations (use existing local images)
  --force-rebuild          Rebuild all local images without cache
  --rebuild-builder        Force rebuild the builder image only
  --rebuild-student        Force rebuild the student image only
  --rebuild-hub            Force rebuild the JupyterHub image only

Actions:
  --stop-server            Stop the stack and remove student containers, then exit
  --update-lectures        Rebuild the course website only (no Docker stop/start)
  --build-obidoc           Force rebuild of obidoc documentation
  -h, --help               Show this help
EOF
}

dockercompose=$(which docker-compose 2>/dev/null || echo 'docker compose')

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-build)         LOCAL_BUILD=true ;;
        --publish)             PUBLISH=true ;;
        --no-build|--offline)  NO_BUILD=true ;;
        --force-rebuild)       FORCE_REBUILD=true; LOCAL_BUILD=true ;;
        --rebuild-builder)     REBUILD_BUILDER=true; LOCAL_BUILD=true ;;
        --rebuild-student)     REBUILD_STUDENT=true; LOCAL_BUILD=true ;;
        --rebuild-hub)         REBUILD_HUB=true; LOCAL_BUILD=true ;;
        --stop-server)         STOP_SERVER=true ;;
        --update-lectures)     UPDATE_LECTURES=true ;;
        --build-obidoc)        BUILD_OBIDOC=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if $LOCAL_BUILD && $PUBLISH; then
    echo "Error: --local-build and --publish cannot be used together" >&2
    exit 1
fi
if $STOP_SERVER && $UPDATE_LECTURES; then
    echo "Error: --stop-server and --update-lectures cannot be used together" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Image name helpers
# ---------------------------------------------------------------------------

local_image_name() {
    case "$1" in
        hub)     echo "jupyterhub-hub:latest" ;;
        student) echo "jupyterhub-student:latest" ;;
        builder) echo "obijupyterhub-builder:latest" ;;
    esac
}

registry_image_name() {
    echo "${REGISTRY}/obijupyterhub-$1:${2:-latest}"
}

dockerfile_for() {
    case "$1" in
        hub)     echo "Dockerfile.hub" ;;
        student) echo "Dockerfile" ;;
        builder) echo "Dockerfile.builder" ;;
    esac
}

read_version() {
    local vfile="${SCRIPT_DIR}/version.txt"
    if [ ! -f "$vfile" ]; then
        echo "Error: version.txt not found at ${vfile}" >&2
        exit 1
    fi
    tr -d '[:space:]' < "$vfile"
}

# Set image names based on mode
if $LOCAL_BUILD; then
    BUILDER_IMAGE=$(local_image_name builder)
    HUB_IMAGE=$(local_image_name hub)
    STUDENT_IMAGE=$(local_image_name student)
else
    BUILDER_IMAGE=$(registry_image_name builder)
    HUB_IMAGE=$(registry_image_name hub)
    STUDENT_IMAGE=$(registry_image_name student)
fi

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

get_file_timestamp() {
    local file="$1"
    case "$(uname -s)" in
        Linux)  stat -c %Y "$file" ;;
        Darwin) stat -f %m "$file" ;;
        *)      echo "Système non supporté" >&2; return 1 ;;
    esac
}

check_if_image_needs_rebuild() {
    local image_name="$1"
    local dockerfile="$2"
    local force="${3:-false}"

    echo -e "${BLUE}Checking image ${image_name}...${NC}"

    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker image ${image_name} doesn't exist.${NC}"
        return 0
    fi

    if $FORCE_REBUILD || $force; then
        echo -e "${YELLOW}Docker image build is forced.${NC}"
        return 0
    fi

    if [ -f "$dockerfile" ]; then
        local dockerfile_mtime
        dockerfile_mtime=$(get_file_timestamp "$dockerfile" 2>/dev/null || echo 0)
        local image_created
        image_created=$(docker image inspect "$image_name" --format='{{.Created}}' 2>/dev/null \
              | sed -E 's/\.[0-9]+//' \
              | (read d; if [[ "$(uname -s)" == "Darwin" ]]; then date -ju -f "%Y-%m-%dT%H:%M:%S" "${d%Z}" +%s; else date -d "$d" +%s; fi) 2>/dev/null || echo 0)

        echo -e "${BLUE}Docker image ${image_name} created at: ${image_created}.${NC}"
        echo -e "${BLUE}Docker file ${dockerfile} modified at: ${dockerfile_mtime}.${NC}"

        if [ "$dockerfile_mtime" -gt "$image_created" ]; then
            echo -e "${YELLOW}Dockerfile is newer than image, rebuild needed${NC}"
            return 0
        fi
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Builder image (local-build mode)
# ---------------------------------------------------------------------------

build_builder_image() {
    if check_if_image_needs_rebuild "$(local_image_name builder)" "Dockerfile.builder" "$REBUILD_BUILDER"; then
        local build_flag=()
        if $FORCE_REBUILD || $REBUILD_BUILDER; then build_flag+=(--no-cache); fi
        echo ""
        echo -e "${BLUE}Building builder image...${NC}"
        docker build "${build_flag[@]}" -t "$(local_image_name builder)" -f Dockerfile.builder .
    else
        echo -e "${BLUE}Builder image is up to date, skipping build.${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Student + Hub images (local-build mode)
# ---------------------------------------------------------------------------

build_images() {
    if $NO_BUILD; then
        echo -e "${YELLOW}Skipping image builds (offline/no-build mode).${NC}"
        return
    fi

    if check_if_image_needs_rebuild "$(local_image_name student)" "Dockerfile" "$REBUILD_STUDENT"; then
        local student_flag=()
        if $FORCE_REBUILD || $REBUILD_STUDENT; then student_flag+=(--no-cache); fi
        echo ""
        echo -e "${BLUE}Building student image...${NC}"
        docker build "${student_flag[@]}" -t "$(local_image_name student)" -f Dockerfile .
    else
        echo -e "${BLUE}Student image is up to date, skipping build.${NC}"
    fi

    if check_if_image_needs_rebuild "$(local_image_name hub)" "Dockerfile.hub" "$REBUILD_HUB"; then
        local hub_flag=()
        if $FORCE_REBUILD || $REBUILD_HUB; then hub_flag+=(--no-cache); fi
        echo ""
        echo -e "${BLUE}Building JupyterHub image...${NC}"
        docker build "${hub_flag[@]}" -t "$(local_image_name hub)" -f Dockerfile.hub .
    else
        echo -e "${BLUE}JupyterHub image is up to date, skipping build.${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Pull images from registry (default mode)
# ---------------------------------------------------------------------------

pull_images() {
    if $NO_BUILD; then
        echo -e "${YELLOW}Skipping image pull (offline/no-build mode).${NC}"
        return
    fi
    echo ""
    echo -e "${BLUE}Pulling images from registry...${NC}"
    docker pull "$BUILDER_IMAGE"
    docker pull "$HUB_IMAGE"
    docker pull "$STUDENT_IMAGE"
}

# ---------------------------------------------------------------------------
# Multi-arch build + push to registry (--publish mode)
# ---------------------------------------------------------------------------

ensure_buildx_builder() {
    docker buildx inspect "$BUILDX_BUILDER_NAME" >/dev/null 2>&1 \
        || docker buildx create --name "$BUILDX_BUILDER_NAME" --driver docker-container --bootstrap
}

publish_images() {
    local version
    version=$(read_version)

    # docker buildx --push uses Docker's own credential store, independent of
    # skopeo. Verify auth early to get a clear error before a long build.
    echo -e "${BLUE}Checking registry authentication...${NC}"
    local registry_host="${REGISTRY%%/*}"
    if ! docker login "$registry_host" >/dev/null 2>&1; then
        echo -e "${YELLOW}Not logged in to ${registry_host}. Running docker login...${NC}"
        docker login "$registry_host" || {
            echo "Error: authentication to ${registry_host} failed." >&2
            echo "Run: docker login ${registry_host}" >&2
            exit 1
        }
    fi

    echo ""
    echo -e "${BLUE}Publishing images (version ${version}) to ${REGISTRY}${NC}"
    echo -e "${BLUE}Platforms: ${PLATFORMS}${NC}"

    ensure_buildx_builder

    local names=(builder student hub)
    local dockerfiles=(Dockerfile.builder Dockerfile Dockerfile.hub)

    for i in "${!names[@]}"; do
        local name="${names[$i]}"
        local df="${dockerfiles[$i]}"
        local remote="${REGISTRY}/obijupyterhub-${name}"

        echo ""
        echo -e "${BLUE}Building and pushing ${name} image...${NC}"
        docker buildx build \
            --builder "$BUILDX_BUILDER_NAME" \
            --platform "$PLATFORMS" \
            --tag "${remote}:latest" \
            --tag "${remote}:${version}" \
            --file "${df}" \
            --push \
            .
        echo -e "${GREEN}  ${remote}:latest${NC}"
        echo -e "${GREEN}  ${remote}:${version}${NC}"
    done

    echo ""
    echo -e "${GREEN}All images published (version ${version}).${NC}"
}

# ---------------------------------------------------------------------------
# Builder container (for website / docs)
# ---------------------------------------------------------------------------

run_in_builder() {
    docker run --rm \
        -v "${SCRIPT_DIR}:/workspace" \
        -v "${SCRIPT_DIR}/jupyterhub_volumes/builder/R_packages:/usr/local/lib/R/site-library" \
        -e "R_LIBS=/opt/R/builder-packages:/usr/local/lib/R/site-library" \
        -w /workspace \
        "$BUILDER_IMAGE" \
        bash -c "$1"
}

# ---------------------------------------------------------------------------
# Stack management
# ---------------------------------------------------------------------------

stop_stack() {
    echo -e "${BLUE}Stopping existing containers...${NC}"
    HUB_IMAGE="$HUB_IMAGE" STUDENT_IMAGE="$STUDENT_IMAGE" \
        ${dockercompose} down 2>/dev/null || true

    echo -e "${BLUE}Cleaning up student containers...${NC}"
    docker ps -aq --filter name=jupyter- | xargs -r docker rm -f 2>/dev/null || true
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

start_stack() {
    echo ""
    echo -e "${BLUE}Starting JupyterHub...${NC}"
    HUB_IMAGE="$HUB_IMAGE" STUDENT_IMAGE="$STUDENT_IMAGE" \
        ${dockercompose} up -d --remove-orphans

    echo ""
    echo -e "${YELLOW}Waiting for JupyterHub to start...${NC}"
    sleep 3
}

print_success() {
    if docker ps | grep -q jupyterhub; then
        local version
        version=$(read_version 2>/dev/null || echo "?")
        echo ""
        echo -e "${GREEN}JupyterHub is running! (version ${version})${NC}"
        echo ""
        echo "-------------------------------------------"
        echo -e "${GREEN}JupyterHub available at: http://localhost:8888${NC}"
        echo "-------------------------------------------"
        echo ""
        echo "Images in use:"
        echo "   Hub:     ${HUB_IMAGE}"
        echo "   Student: ${STUDENT_IMAGE}"
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

# ---------------------------------------------------------------------------
# Setup volume directories
# ---------------------------------------------------------------------------

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

if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
    echo "Error: Run this script from the OBIJupyterHub directory"
    exit 1
fi

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------

if $STOP_SERVER; then
    stop_stack
    popd >/dev/null
    exit 0
fi

if $UPDATE_LECTURES; then
    if $LOCAL_BUILD; then
        build_builder_image
    elif ! $NO_BUILD; then
        docker pull "$BUILDER_IMAGE" 2>/dev/null \
            || echo -e "${YELLOW}Could not pull builder image, using local cache.${NC}"
    fi
    build_website
    popd >/dev/null
    exit 0
fi

stop_stack

if $PUBLISH; then
    publish_images
    pull_images   # pull the freshly published images into the local daemon
elif $LOCAL_BUILD; then
    build_builder_image
    build_images
else
    pull_images   # default: pull from registry
fi

build_website
build_obidoc
start_stack

popd >/dev/null
print_success
