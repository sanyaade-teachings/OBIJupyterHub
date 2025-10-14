#!/usr/bin/env bash
set -e

# === Variables ===
WORKDIR="$PWD"
NETWORK="jupyterhub-net"
HUB_IMAGE="jupyterhub-hub"
USER_IMAGE="jupyter-tp-singleuser"

# === Préparation ===
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[1/5] Création du réseau Docker..."
docker network inspect $NETWORK >/dev/null 2>&1 || docker network create $NETWORK

echo "[2/5] Construction des images..."
docker build -t $USER_IMAGE -f Dockerfile .
docker build -t $HUB_IMAGE -f Dockerfile.hub .

echo "[3/5] Lancement de JupyterHub..."
docker compose up -d

echo "[4/5] Hub accessible sur http://localhost:8888"
echo "      Login avec n'importe quel nom et mot de passe : metabar2025"

echo "[5/5] Pour voir les utilisateurs actifs :"
echo "      docker ps | grep jupyterhub-user"

echo "Terminé."
