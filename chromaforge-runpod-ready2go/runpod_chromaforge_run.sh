#!/bin/bash
# =============================================================================
# runpod_chromaforge_run.sh
# =============================================================================
# Rôle   : Vérifie l'environnement, restaure le venv depuis l'archive si absent,
#           télécharge les modèles Chroma si absents, génère webui-user.sh,
#           puis lance ChromaForge (webui.sh).
#           En cas d'échec de restauration, webui.sh reconstruit le venv.
#
# Emplacement : /workspace/runpod_chromaforge_run.sh  (volume persistant)
# Invocation  : Automatiquement via runpod_chromaforge_start.sh au démarrage,
#               ou manuellement depuis un terminal SSH :
#                 bash /workspace/runpod_chromaforge_run.sh
#
# Variables d'environnement attendues (sourcées depuis /etc/rp_environment) :
#   WEBUI_USER     — utilisateur Gradio auth (optionnel)
#   WEBUI_PASSWORD — mot de passe Gradio auth (optionnel)
#   EXTRA_ARGS     — arguments supplémentaires pour webui.py (optionnel)
#                    ex: --pin-shared-memory --cuda-stream
#
# Logs :
#   /workspace/logs/runpod_chromaforge_run.log  — log de ce script
#   /workspace/logs/chromaforge.log              — log de webui.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly APP_DIR="/workspace/chromaforge"
readonly HF_VENV="/workspace/venvs/hf"
readonly HF_BIN="$HF_VENV/bin/hf"
readonly LOG_DIR="/workspace/logs"
readonly LOG="$LOG_DIR/runpod_chromaforge_run.log"
readonly CF_LOG="$LOG_DIR/chromaforge.log"
readonly VENV_ARCHIVE_URL="https://ipfs.filebase.io/ipfs/QmWVUupc1nyRp8P6NUoXDDBybGmAxK5nsG13NaDohMbXcy"
readonly VENV_ARCHIVE_LOCAL="/workspace/venv.tar.zst"

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

log()  { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
fail() { echo "[$(date '+%H:%M:%S')] ERREUR : $*" | tee -a "$LOG" >&2; exit 1; }

# Télécharge un modèle HuggingFace si le fichier de destination est absent.
# Usage : hf_download <repo_id> <filename> <local_dir>
hf_download() {
    local repo_id="$1" filename="$2" local_dir="$3"
    local dest="$local_dir/$filename"

    if [ -f "$dest" ]; then
        log "  OK (présent) : $filename"
        return 0
    fi

    log "  Téléchargement : $filename  (depuis $repo_id)"
    mkdir -p "$local_dir"
    "$HF_BIN" download "$repo_id" "$filename" --local-dir "$local_dir" \
        || fail "Échec téléchargement $filename depuis $repo_id"
    [ -f "$dest" ] || fail "$filename absent après téléchargement"
    log "  OK : $filename  $(du -h "$dest" | cut -f1)"
}

# =============================================================================
# [1/7] VÉRIFICATION DES PRÉREQUIS SYSTÈME
# =============================================================================
check_prerequisites() {
    log "[1/7] Vérification prérequis"

    # Sourcer /etc/rp_environment si disponible — garantit la présence de
    # WEBUI_USER/WEBUI_PASSWORD même si lancé depuis un shell SSH sans source.
    # shellcheck source=/dev/null
    [ -f /etc/rp_environment ] && source /etc/rp_environment || true

    command -v python3 &>/dev/null \
        || fail "python3 non disponible"

    id forge &>/dev/null \
        || fail "L'user 'forge' n'existe pas — exécuter runpod_chromaforge_start.sh d'abord"

    # Cloner le repo chromaforge si absent du volume persistant
    if [ ! -d "$APP_DIR" ]; then
        log "  Clonage de chromaforge depuis GitHub..."
        git clone https://github.com/zobrak/chromaforge-runpod "$APP_DIR" \
            || fail "Échec du clonage de chromaforge"
        log "  OK : chromaforge cloné"
    fi

    [ -f "$APP_DIR/webui.sh" ] \
        || fail "webui.sh introuvable dans $APP_DIR"

    log "  OK : tous les prérequis sont satisfaits"
}

# =============================================================================
# [2/7] VÉRIFICATION DES VARIABLES D'ENVIRONNEMENT
# =============================================================================
check_env() {
    log "[2/7] Vérification variables d'environnement"

    if [ -n "${WEBUI_USER:-}" ] && [ -n "${WEBUI_PASSWORD:-}" ]; then
        log "  OK : authentification Gradio activée (user : $WEBUI_USER)"
    else
        log "  WARN : WEBUI_USER ou WEBUI_PASSWORD non définie — lancement sans authentification"
    fi
    if [ -n "${EXTRA_ARGS:-}" ]; then
        log "  OK : EXTRA_ARGS définie : $EXTRA_ARGS"
    fi
}

# =============================================================================
# [3/7] RESTAURATION DU VENV DEPUIS L'ARCHIVE
# =============================================================================
# Le venv pré-construit est hébergé sur Filebase IPFS (~3.6 Go compressé).
# Durée estimée : 2-3 min téléchargement + 20-25 min décompression sur NV.
# Si le venv existe déjà sur le volume persistant, étape skippée.
# En cas d'échec, webui.sh reconstruit le venv depuis zéro (fallback).
# =============================================================================
restore_venv() {
    log "[3/7] Restauration du venv"

    local venv_python="$APP_DIR/venv/bin/python"

    if [ -x "$venv_python" ]; then
        log "  OK (présent) : venv forge déjà en place"
        return 0
    fi

    log "  Venv absent — téléchargement de l'archive depuis Filebase IPFS"

    # S'assurer que zstd est disponible
    if ! command -v zstd &>/dev/null; then
        log "  zstd absent — tentative d'installation"
        apt-get install -y zstd &>/dev/null \
            || {
                log "  WARN : zstd indisponible — reconstruction du venv par webui.sh"
                return 0
            }
    fi

    # Téléchargement — --progress=bar:force affiche la progression même hors TTY
    wget --no-verbose --show-progress --progress=bar:force \
        -O "$VENV_ARCHIVE_LOCAL" "$VENV_ARCHIVE_URL" \
        || {
            log "  WARN : échec téléchargement — reconstruction du venv par webui.sh"
            rm -f "$VENV_ARCHIVE_LOCAL"
            return 0
        }

    log "  Archive téléchargée : $(du -h "$VENV_ARCHIVE_LOCAL" | cut -f1)"

    # Vérification intégrité SHA256 depuis /opt/venv.tar.zst.sha256
    local sha256_file="/opt/venv.tar.zst.sha256"
    if [ -f "$sha256_file" ]; then
        log "  Vérification SHA256..."
        local actual_sha expected_sha
        actual_sha=$(sha256sum "$VENV_ARCHIVE_LOCAL" | cut -d' ' -f1)
        expected_sha=$(awk '{print $1}' "$sha256_file")
        if [ "$actual_sha" != "$expected_sha" ]; then
            log "  WARN : SHA256 invalide — archive corrompue, reconstruction par webui.sh"
            rm -f "$VENV_ARCHIVE_LOCAL"
            return 0
        fi
        log "  OK : SHA256 vérifié"
    else
        log "  WARN : /opt/venv.tar.zst.sha256 absent — vérification SHA256 ignorée"
    fi

    # Décompression — l'archive contient venv/ relatif à APP_DIR.
    # pv affiche le débit et la progression en temps réel.
    # La décompression vers le NV réseau peut prendre 20-25 minutes (~10 Go).
    log "  Décompression en cours (20-25 minutes)..."
    local t_start t_end elapsed
    t_start=$(date +%s)

    if ! command -v pv &>/dev/null; then
        apt-get install -y pv &>/dev/null || true
    fi

    if command -v pv &>/dev/null; then
        pv "$VENV_ARCHIVE_LOCAL" | tar -I zstd -x -C "$APP_DIR"
        local pv_status
        local tar_status
        pv_status="${PIPESTATUS[0]}"
        tar_status="${PIPESTATUS[1]}"
        if [ "$pv_status" -ne 0 ] || [ "$tar_status" -ne 0 ]; then
            log "  WARN : échec décompression — reconstruction du venv par webui.sh"
            rm -f "$VENV_ARCHIVE_LOCAL"
            return 0
        fi
    else
        tar -I zstd -xf "$VENV_ARCHIVE_LOCAL" -C "$APP_DIR" \
            || {
                log "  WARN : échec décompression — reconstruction du venv par webui.sh"
                rm -f "$VENV_ARCHIVE_LOCAL"
                return 0
            }
    fi

    t_end=$(date +%s)
    elapsed=$(( t_end - t_start ))
    log "  Décompression terminée en $((elapsed / 60))m$((elapsed % 60))s"

    rm -f "$VENV_ARCHIVE_LOCAL"

    if [ ! -x "$venv_python" ]; then
        log "  WARN : venv absent après décompression — reconstruction par webui.sh"
        return 0
    fi

    log "  OK : venv restauré depuis l'archive"
}

# =============================================================================
# [4/7] INSTALLATION DE HUGGINGFACE CLI
# =============================================================================
# Le binaire s'appelle "hf" depuis huggingface_hub >= 0.23
# (remplace l'ancien huggingface-cli, déprécié).
# Installé dans un venv dédié pour ne pas polluer l'environnement système.
# =============================================================================
setup_hf_cli() {
    log "[4/7] Vérification huggingface CLI"

    if [ -x "$HF_BIN" ]; then
        log "  OK (présent) : $HF_BIN"
        return 0
    fi

    # Venv HF existe mais sans le binaire "hf"
    if [ -d "$HF_VENV" ]; then
        # Vérifier que pip est présent — si non, le venv est corrompu
        if [ ! -x "$HF_VENV/bin/pip" ]; then
            log "  Venv HF corrompu (pip absent) — suppression et recréation"
            rm -rf "$HF_VENV"
            # Laisser tomber dans le bloc de création ci-dessous
        else
            log "  Mise à jour huggingface_hub (hf absent du venv existant)"
            "$HF_VENV/bin/pip" install --quiet --upgrade "huggingface_hub" \
                || fail "Échec mise à jour huggingface_hub"
            [ -x "$HF_BIN" ] || fail "hf introuvable après mise à jour : $HF_BIN"
            log "  OK : huggingface_hub mis à jour"
            return 0
        fi
    fi

    # Création du venv HF et installation
    log "  Installation de huggingface_hub dans $HF_VENV"
    python3 -m venv "$HF_VENV" \
        || fail "Impossible de créer le venv HF : $HF_VENV"
    "$HF_VENV/bin/pip" install --quiet --upgrade pip \
        || fail "Échec upgrade pip dans le venv HF"
    "$HF_VENV/bin/pip" install --quiet "huggingface_hub" \
        || fail "Échec installation huggingface_hub"
    [ -x "$HF_BIN" ] || fail "hf introuvable après installation : $HF_BIN"
    log "  OK : huggingface_hub installé ($HF_BIN)"
}

# =============================================================================
# [5/7] TÉLÉCHARGEMENT DES MODÈLES CHROMA
# =============================================================================
download_models() {
    log "[5/7] Vérification modèles"

    # Chroma1-HD — modèle principal (8.9B paramètres, ~17 Go)
    hf_download "lodestones/Chroma1-HD" \
                "Chroma1-HD.safetensors" \
                "$APP_DIR/models/Stable-diffusion"

    # T5-XXL fp16 — text encoder (~9 Go)
    hf_download "flux-safetensors/flux-safetensors" \
                "t5xxl_fp16.safetensors" \
                "$APP_DIR/models/text_encoder"

    # VAE (~335 Mo)
    hf_download "lodestones/Chroma" \
                "ae.safetensors" \
                "$APP_DIR/models/VAE"

    log "  OK : tous les modèles sont présents"
}

# =============================================================================
# [6/7] GÉNÉRATION DE webui-user.sh
# =============================================================================
# webui.sh source webui-user.sh — seul mécanisme garanti pour transmettre
# COMMANDLINE_ARGS à forge (auth Gradio notamment). Regénéré à chaque
# lancement pour refléter les variables d'environnement courantes.
# =============================================================================
write_webui_user_sh() {
    log "[6/7] Génération de webui-user.sh"

    local auth_arg=""
    if [ -n "${WEBUI_USER:-}" ] && [ -n "${WEBUI_PASSWORD:-}" ]; then
        auth_arg=" --gradio-auth ${WEBUI_USER}:${WEBUI_PASSWORD}"
    fi
    # Arguments supplémentaires passés via la variable de template RunPod EXTRA_ARGS
    # Exemple : EXTRA_ARGS=--pin-shared-memory --cuda-stream
    local extra_args=""
    if [ -n "${EXTRA_ARGS:-}" ]; then
        extra_args=" ${EXTRA_ARGS}"
    fi

    # Écriture atomique via fichier temporaire — évite un état incohérent
    # si le script est interrompu pendant l'écriture
    local tmp_file
    tmp_file="$(mktemp "$APP_DIR/webui-user.sh.XXXXXX")"

    cat > "$tmp_file" << WEBUIEOF
#!/bin/bash
# =======================================================================
# webui-user.sh — Généré par runpod_chromaforge_run.sh
# Ne pas modifier manuellement : ce fichier est regénéré à chaque lancement
# =======================================================================

# Arguments de lancement transmis à webui.py via launch.py
export COMMANDLINE_ARGS="--listen --port 7860 --skip-torch-cuda-test --enable-insecure-extension-access --cuda-malloc --log-level WARNING${auth_arg}${extra_args}"
WEBUIEOF

    mv "$tmp_file" "$APP_DIR/webui-user.sh"

    log "  OK : webui-user.sh généré"
    # Ne pas logger le mot de passe en clair
    local log_args="--listen --port 7860 --skip-torch-cuda-test --enable-insecure-extension-access --cuda-malloc --log-level WARNING"
    if [ -n "${WEBUI_USER:-}" ] && [ -n "${WEBUI_PASSWORD:-}" ]; then
        log_args="$log_args --gradio-auth ${WEBUI_USER}:***"
    fi
    if [ -n "${EXTRA_ARGS:-}" ]; then
        log_args="$log_args $EXTRA_ARGS"
    fi
    log "  COMMANDLINE_ARGS : $log_args"
}

# =============================================================================
# [7/7] LANCEMENT DE CHROMAFORGE
# =============================================================================
launch_chromaforge() {
    log "[7/7] Lancement ChromaForge"

    # Détection via chemin complet de launch.py pour éviter les faux positifs
    if pgrep -f "$APP_DIR/launch.py" &>/dev/null; then
        log "  OK (déjà actif) : ChromaForge tourne déjà"
        return 0
    fi

    log "  Lancement de webui.sh sous l'user forge..."
    log "  Log chromaforge : $CF_LOG"

    # Activation explicite du venv avant webui.sh — évite la réinstallation
    # des requirements par webui.sh quand le venv n'est pas activé
    su forge -s /bin/bash -c \
        "cd $APP_DIR && source $APP_DIR/venv/bin/activate && $APP_DIR/webui.sh" \
        >> "$CF_LOG" 2>&1 &

    log "  OK : ChromaForge lancé en arrière-plan (PID $!)"
}

# =============================================================================
# SÉQUENCE PRINCIPALE
# =============================================================================
main() {
    # Initialisation des logs — shred pour effacement sécurisé
    mkdir -p "$LOG_DIR"
    for f in "$LOG" "$CF_LOG"; do
        [ -f "$f" ] && { shred -u "$f" 2>/dev/null || rm -f "$f"; }
        touch "$f"
    done

    log "============================================================"
    log " runpod_chromaforge_run.sh — $(date)"
    log "============================================================"

    check_prerequisites  # source /etc/rp_environment ici
    check_env
    restore_venv
    setup_hf_cli
    download_models
    write_webui_user_sh
    launch_chromaforge

    log "============================================================"
    log " Terminé — $(date)"
    log "============================================================"
}

main
