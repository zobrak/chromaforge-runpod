#!/bin/bash
# =============================================================================
# runpod_chromaforge_start.sh
# =============================================================================
# Rôle   : Bootstrap au démarrage du conteneur RunPod.
#           Démarre les services RunPod natifs, crée l'user forge,
#           exporte les variables d'environnement, puis lance
#           automatiquement runpod_chromaforge_run.sh.
#
# Emplacement : /workspace/runpod_chromaforge_start.sh  (volume persistant)
# Invocation  : Lancé automatiquement par docker-entrypoint.sh au démarrage
#               du conteneur RunPod (ENTRYPOINT de l'image Docker).
#
# Variables d'environnement attendues :
#   Secrets RunPod :
#   PUBLIC_KEY       — clé SSH publique (optionnel)
#   JUPYTER_PASSWORD — mot de passe JupyterLab (optionnel)
#   WEBUI_USER       — utilisateur Gradio (optionnel, exporté pour run.sh)
#   WEBUI_PASSWORD   — mot de passe Gradio (optionnel, exporté pour run.sh)
#   Variables de template RunPod :
#   EXTRA_ARGS       — args supplémentaires webui.py ex: --pin-shared-memory
#
# Logs : /workspace/logs/runpod_chromaforge_start.log
# =============================================================================

# Pas de set -e : le conteneur doit rester actif même si une étape échoue

# =============================================================================
# INITIALISATION DU LOG
# =============================================================================
LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/runpod_chromaforge_start.log"
if [ -f "$LOG" ]; then
    shred -u "$LOG" 2>/dev/null || rm -f "$LOG"
fi
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

section() { echo ""; echo "--- $* ---"; }

# =============================================================================
echo ""
echo "============================================================"
echo " ChromaForge — bootstrap  $(date)"
echo "============================================================"

# =============================================================================
# [1/2] SERVICES RUNPOD NATIFS
# =============================================================================
section "[1/2] Services RunPod"

# --- Variables d'environnement -----------------------------------------------
# Exporte les variables utiles dans /etc/rp_environment pour les shells SSH
# qui arrivent après le démarrage du conteneur.
# Utilise printf '%q' pour quoter correctement les valeurs contenant des
# espaces ou caractères spéciaux (notamment PUBLIC_KEY en base64+espace).
{
    while IFS= read -r line; do
        local_key="${line%%=*}"
        local_val="${line#*=}"
        printf 'export %s=%q\n' "$local_key" "$local_val"
    done < <(printenv | grep -E "^RUNPOD_|^WEBUI_|^JUPYTER_|^PUBLIC_KEY|^EXTRA_ARGS")
} > /etc/rp_environment 2>/dev/null || true

# Copier le .bashrc personnalisé depuis le volume persistant.
# Ce fichier contient déjà "source /etc/rp_environment" — les variables
# seront disponibles à chaque login SSH sans source manuel.
if [ -f /workspace/.bashrc ]; then
    cp /workspace/.bashrc /root/.bashrc
    echo "  OK : /workspace/.bashrc copié vers /root/.bashrc"
else
    echo "  SKIP : /workspace/.bashrc absent"
fi

# --- Nginx -------------------------------------------------------------------
if command -v nginx &>/dev/null; then
    if pgrep -x nginx &>/dev/null; then
        echo "  OK (déjà actif) : nginx"
    else
        nginx \
            && echo "  OK : nginx démarré" \
            || echo "  WARN : nginx n'a pas pu démarrer"
    fi
else
    echo "  SKIP : nginx non disponible"
fi

# --- SSH ---------------------------------------------------------------------
# Activé uniquement si PUBLIC_KEY est définie dans les secrets RunPod.
if [ -n "${PUBLIC_KEY:-}" ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    # Écriture atomique pour éviter un fichier partiellement écrit
    printf '%s\n' "$PUBLIC_KEY" > /root/.ssh/authorized_keys.tmp \
        && mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys \
        || rm -f /root/.ssh/authorized_keys.tmp
    chmod 600 /root/.ssh/authorized_keys
    # Générer les clés hôtes si absentes (premier démarrage conteneur)
    [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -A &>/dev/null

    # Configuration SSH sécurisée via drop-in — ne pas modifier sshd_config
    # directement pour ne pas interférer avec la config du template RunPod
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-chromaforge.conf << 'SSHEOF'
PermitRootLogin without-password
MaxAuthTries 15
PasswordAuthentication no
SSHEOF
    echo "  OK : configuration SSH appliquée"

    if pgrep -x sshd &>/dev/null; then
        echo "  OK (déjà actif) : sshd"
    else
        service ssh start &>/dev/null \
            && echo "  OK : sshd démarré" \
            || echo "  WARN : sshd n'a pas pu démarrer"
    fi
else
    echo "  SKIP : sshd (PUBLIC_KEY non définie)"
fi

# --- JupyterLab --------------------------------------------------------------
# Activé uniquement si JUPYTER_PASSWORD est définie dans les secrets RunPod.
# Le mot de passe est passé via variable d'environnement au subprocess Python
# pour éviter tout problème d'échappement avec les guillemets ou caractères
# spéciaux dans le mot de passe.
if [ -n "${JUPYTER_PASSWORD:-}" ]; then
    if pgrep -f "jupyter" &>/dev/null; then
        echo "  OK (déjà actif) : jupyter"
    else
        if python3 -c "from jupyter_server.auth import passwd" &>/dev/null; then
            HASHED_PW="$(JUPYTER_PASSWORD="${JUPYTER_PASSWORD}" python3 -c \
                'import os; from jupyter_server.auth import passwd
print(passwd(os.environ["JUPYTER_PASSWORD"]))')"
            jupyter lab \
                --ip=0.0.0.0 \
                --port=8888 \
                --no-browser \
                --allow-root \
                --notebook-dir=/workspace \
                --ServerApp.password="${HASHED_PW}" \
                &>"$LOG_DIR/jupyter.log" &
            echo "  OK : jupyter démarré (port 8888, log : $LOG_DIR/jupyter.log)"
        else
            echo "  WARN : jupyter_server non disponible — JupyterLab non lancé"
        fi
    fi
else
    echo "  SKIP : jupyter (JUPYTER_PASSWORD non définie)"
fi

# =============================================================================
# [2/2] USER FORGE
# =============================================================================
section "[2/2] User forge"

# forge est l'utilisateur non-root requis par webui.sh de chromaforge.
# /etc/passwd est éphémère sur RunPod — recréer forge à chaque démarrage.
# useradd retourne le code 9 si l'user existe déjà — ignoré silencieusement.
useradd -m forge 2>/dev/null \
    && echo "  OK : user forge créé" \
    || echo "  OK (déjà existant) : forge"

# =============================================================================
echo ""
echo "============================================================"
echo " Bootstrap terminé  $(date)"
echo " Log : $LOG"
echo ""
echo " ChromaForge démarre automatiquement..."
echo "============================================================"

# Lancement automatique de ChromaForge
# Attente que le réseau soit opérationnel avant de lancer run.sh
# (les téléchargements échouent si run.sh démarre avant l'init réseau)
if [ -f /workspace/runpod_chromaforge_run.sh ]; then
    echo " Attente du réseau..."
    _retries=0
    until curl -sf --max-time 3 https://zobrak.net &>/dev/null; do
        _retries=$(( _retries + 1 ))
        if [ "$_retries" -ge 30 ]; then
            echo " WARN : réseau indisponible après 90s — lancement quand même"
            break
        fi
        sleep 3
    done
    echo " Lancement automatique de runpod_chromaforge_run.sh..."
    bash /workspace/runpod_chromaforge_run.sh &
else
    echo " WARN : runpod_chromaforge_run.sh absent — lancer manuellement"
fi

# Maintien du conteneur actif.
# `wait` seul retourne immédiatement sans processus background dans ce shell.
# La boucle garantit que le conteneur reste actif indéfiniment.
while true; do sleep 60; done
