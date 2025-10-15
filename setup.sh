#!/bin/bash

# JupyterHub startup script for labs
# Usage: ./start-jupyterhub.sh

set -e  # Stop on error

echo "🚀 Starting JupyterHub for Lab"
echo "=============================="
echo ""

# Colors for display
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Create volumes if they don't exist
echo ""
echo -e "${BLUE}💾 Creating shared volumes...${NC}"
docker volume create jupyterhub-shared 2>/dev/null || echo "  Volume jupyterhub-shared already exists"
docker volume create jupyterhub-course 2>/dev/null || echo "  Volume jupyterhub-course already exists"

# Start the stack
echo ""
echo -e "${BLUE}🚀 Starting JupyterHub...${NC}"
docker-compose up -d

# Wait for service to be ready
echo ""
echo -e "${YELLOW}⏳ Waiting for JupyterHub to start...${NC}"
sleep 3

# Check that container is running
if docker ps | grep -q jupyterhub; then
    echo ""
    echo -e "${GREEN}✅ JupyterHub is running!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🌐 JupyterHub available at: http://localhost:8000${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📝 Password: metabar2025"
    echo "👥 Students can connect with any username"
    echo ""
    echo "📂 Each student will have access to:"
    echo "   - work/   : personal workspace"
    echo "   - shared/ : shared workspace"
    echo "   - course/ : course files (read-only)"
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
