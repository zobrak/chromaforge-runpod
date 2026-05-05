# Changelog

Toutes les modifications notables de ce projet sont documentées ici.
Format : [SemVer](https://semver.org/) — MAJEUR.MINEUR.PATCH

---

## [1.0.0] — 2026-05-04

### Première version stable

#### Image Docker
- Base : `runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04`
- Suppression du PPA deadsnakes (timeouts apt)
- `apt-get full-upgrade` au build
- Ajout de `zstd` dans les dépendances apt
- `docker-entrypoint.sh` : écrase toujours les scripts depuis `/opt` vers `/workspace` au démarrage — garantit la cohérence après rebuild

#### runpod_chromaforge_start.sh
- Bootstrap minimal : nginx, SSH, JupyterLab, user forge
- Export des variables d'environnement vers `/etc/rp_environment`
- Support `EXTRA_ARGS` (variable de template RunPod)
- Config SSH sécurisée via drop-in `/etc/ssh/sshd_config.d/99-chromaforge.conf`
- User forge recréé inconditionnellement à chaque boot (`/etc/passwd` éphémère sur RunPod)
- Attente réseau active sur `ipfs.filebase.io` avant lancement de `run.sh`
- Lancement automatique de `runpod_chromaforge_run.sh` en arrière-plan

#### runpod_chromaforge_run.sh
- Restauration du venv depuis Filebase IPFS (CID : `QmWVUupc1nyRp8P6NUoXDDBybGmAxK5nsG13NaDohMbXcy`)
- Vérification intégrité SHA256 depuis `/opt/venv.tar.zst.sha256`
- Fallback automatique vers webui.sh si restauration échoue
- Détection et recréation automatique du venv HF corrompu
- Téléchargement des modèles Chroma1-HD, t5xxl_fp16, ae via `hf` CLI
- Génération atomique de `webui-user.sh` avec `COMMANDLINE_ARGS`
- Flags par défaut : `--listen --port 7860 --skip-torch-cuda-test --enable-insecure-extension-access --cuda-malloc --log-level WARNING`
- Lancement de ChromaForge sous l'user forge avec activation explicite du venv
- Support `EXTRA_ARGS` pour arguments supplémentaires à webui.py
