#!/bin/bash
# =============================================================================
# docker-entrypoint.sh
# =============================================================================
# Point d'entrée du conteneur RunPod.
# Copie toujours les scripts et le .bashrc depuis /opt (image) vers
# /workspace (NV) — garantit que la version de l'image est toujours active.
#
# Le clonage de chromaforge, la restauration du venv et le téléchargement
# des modèles sont gérés par runpod_chromaforge_run.sh (lancement manuel).
# =============================================================================

set -e

# Vérifier que /workspace est accessible (NV monté)
if [ ! -d /workspace ]; then
    echo "[entrypoint] ERREUR : /workspace inaccessible — volume persistant non monté ?"
    exit 1
fi

# Copier les scripts depuis l'image vers le NV — toujours écrasé pour
# garantir que la version de l'image est active après un rebuild
echo "[entrypoint] Mise à jour des scripts depuis l'image..."
cp /opt/runpod_chromaforge_start.sh /workspace/runpod_chromaforge_start.sh
cp /opt/runpod_chromaforge_run.sh /workspace/runpod_chromaforge_run.sh
chmod +x /workspace/runpod_chromaforge_start.sh \
          /workspace/runpod_chromaforge_run.sh

# Copier le .bashrc uniquement si absent — permet les personnalisations
# locales sans les écraser à chaque démarrage
if [ ! -f /workspace/.bashrc ]; then
    echo "[entrypoint] Copie de .bashrc vers /workspace..."
    cp /opt/.bashrc /workspace/.bashrc
fi

# Lancer le bootstrap
exec bash /workspace/runpod_chromaforge_start.sh
