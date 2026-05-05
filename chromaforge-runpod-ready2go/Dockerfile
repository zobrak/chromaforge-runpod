# =============================================================================
# Dockerfile — ChromaForge RunPod
# =============================================================================
# Base   : runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04
# Build  : docker buildx build --platform linux/amd64 -t z0brak/chromaforge-runpod-ready2go:latest --push .
#
# Ce que contient l'image :
#   - Toutes les dépendances apt requises par chromaforge
#   - User forge
#   - Scripts runpod_chromaforge_start.sh et runpod_chromaforge_run.sh
#   - .bashrc personnalisé
# Au démarrage, l'entrypoint copie tout vers /workspace (NV).
# Compatible avec un volume persistant vierge.
#
# Ce qui reste sur le volume persistant (NV RunPod) :
#   - Le venv forge (~10 Go) — restauré depuis zobrak.net/downloads au 1er boot
#   - Les modèles Chroma (~27 Go) — téléchargés depuis HuggingFace au 1er boot
#   - Les outputs générés
#   - /workspace/.bashrc
#
# Container Start Command dans RunPod : laisser VIDE
#   L'ENTRYPOINT de l'image est utilisé automatiquement.
# =============================================================================

FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

# Métadonnées
LABEL maintainer="zobrak"
LABEL description="ChromaForge on RunPod — Flux/Chroma image generation"
LABEL version="1.0"

# Évite les interactions lors des installations apt
ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# DÉPÔTS APT — nettoyage
# =============================================================================
# Suppression du PPA deadsnakes : inutile (Python 3.10 système suffisant)
# et source de timeouts apt (~38s par apt-get update).
RUN rm -f /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-jammy.list

# =============================================================================
# MISE À JOUR SYSTÈME ET DÉPENDANCES APT
# =============================================================================
RUN apt-get update -qq && \
    apt-get full-upgrade -y && \
    apt-get install -y \
        bc \
        curl \
        git \
        google-perftools \
        libcairo2-dev \
        libglib2.0-0 \
        libgl1 \
        libgoogle-perftools-dev \
        nano \
        pkg-config \
        python3-dev \
        python3-venv \
        wget \
        zstd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# SCRIPTS DE DÉMARRAGE
# =============================================================================
# Copiés dans /opt/ — seront disponibles même sans volume persistant.
# L'utilisateur doit également les avoir sur /workspace pour la persistance.
COPY runpod_chromaforge_start.sh /opt/runpod_chromaforge_start.sh
COPY runpod_chromaforge_run.sh /opt/runpod_chromaforge_run.sh
COPY .bashrc /opt/.bashrc
RUN chmod +x /opt/runpod_chromaforge_start.sh /opt/runpod_chromaforge_run.sh

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================
# L'ENTRYPOINT est docker-entrypoint.sh — il copie les scripts depuis
# /opt vers /workspace si absents, puis lance start.sh.
# Dans RunPod, laisser le champ "Container Start Command" VIDE —
# l'ENTRYPOINT de l'image est utilisé automatiquement.
# Le clonage de chromaforge et la restauration du venv sont gérés par run.sh.
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 7860 8888 22

ENTRYPOINT ["/docker-entrypoint.sh"]
