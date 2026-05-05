# ChromaForge RunPod — Ready to Go

**Version 1.0.2**

Fork de Stable Diffusion WebUI Forge optimisé pour le modèle Chroma, déployable sur RunPod avec un volume persistant vierge. ChromaForge démarre automatiquement au lancement du pod.

## Ce que contient cette image

- Ubuntu 22.04 + CUDA 12.1.1 + Python 3.10 (paquets système à jour)
- Toutes les dépendances système requises par ChromaForge
- Scripts `runpod_chromaforge_start.sh` et `runpod_chromaforge_run.sh`
- `.bashrc` personnalisé
- `venv.tar.zst.sha256` — hash de vérification d'intégrité du venv

## Ce qui est géré automatiquement

### Au premier démarrage (volume vierge)

- Clonage de [zobrak/chromaforge-runpod](https://github.com/zobrak/chromaforge-runpod)
- Restauration du venv depuis Filebase IPFS (~3.6 Go compressés, ~25 min d'écriture sur NV)
  - Intégrité vérifiée par SHA256 après téléchargement
  - Fallback automatique vers webui.sh si échec
- Téléchargement des modèles Chroma depuis HuggingFace :
  - `Chroma1-HD.safetensors` (~17 Go)
  - `t5xxl_fp16.safetensors` (~9 Go)
  - `ae.safetensors` (~335 Mo)

### Aux démarrages suivants

Démarrage complet en moins d'une minute — venv et modèles déjà présents sur le volume.

## Configuration du pod RunPod

| Paramètre | Valeur |
|---|---|
| Container Image | `z0brak/chromaforge-runpod-ready2go:latest` |
| Container Start Command | *(laisser vide)* |
| Expose HTTP Ports | `7860, 8888` |
| Expose TCP Ports | `22` |
| Volume Mount Path | `/workspace` |
| Volume Size | 100 Go recommandé |

### Secrets à configurer

| Nom | Description | Requis |
|---|---|---|
| `PUBLIC_KEY` | Clé SSH publique | Recommandé |
| `WEBUI_USER` | Identifiant Gradio pour l'UI | Recommandé |
| `WEBUI_PASSWORD` | Mot de passe Gradio | Recommandé |
| `JUPYTER_PASSWORD` | Mot de passe JupyterLab | Optionnel |

### Variables de template

| Nom | Description | Exemple |
|---|---|---|
| `EXTRA_ARGS` | Arguments supplémentaires passés à webui.py | `--pin-shared-memory --cuda-stream` |

`EXTRA_ARGS` permet de personnaliser le comportement de ChromaForge sans rebuild de l'image. Les flags suivants sont inclus par défaut :

```
--listen --port 7860 --skip-torch-cuda-test
--enable-insecure-extension-access --cuda-malloc --log-level WARNING
```

## Accès à l'interface

ChromaForge démarre automatiquement. L'UI est accessible via :

**RunPod Console → Connect → HTTP Service → Port 7860**

## Paramètres recommandés pour Chroma1-HD

| Paramètre | Valeur recommandée |
|---|---|
| Sampler | Euler |
| Schedule | Beta |
| Steps | 26 à 40 |
| CFG Scale | 3 à 4 |
| Distilled CFG | 3.5 (valeur par défaut) |
| Negative prompt | Fonctionne — recommandé |

## Logs

| Fichier | Contenu |
|---|---|
| `/workspace/logs/runpod_chromaforge_start.log` | Bootstrap système |
| `/workspace/logs/runpod_chromaforge_run.log` | Lancement ChromaForge |
| `/workspace/logs/chromaforge.log` | WebUI Forge / ChromaForge |

## GPU recommandé

RTX 4090 (24 Go VRAM) — requis pour Chroma1-HD en inférence.

## Build de l'image

Les fichiers de build sont disponibles dans le dépôt GitHub :

**[zobrak/chromaforge-runpod → dossier `chromaforge-runpod-ready2go`](https://github.com/zobrak/chromaforge-runpod/tree/main/chromaforge-runpod-ready2go)**

```
chromaforge-runpod-ready2go/
├── Dockerfile
├── docker-entrypoint.sh
├── runpod_chromaforge_start.sh
├── runpod_chromaforge_run.sh
├── venv.tar.zst.sha256
├── .bashrc
├── README.md
└── CHANGELOG.md
```

## Sources

- [ChromaForge (fork RunPod)](https://github.com/zobrak/chromaforge-runpod)
- [ChromaForge (original)](https://github.com/maybleMyers/chromaforge)
- [Modèle Chroma1-HD](https://huggingface.co/lodestones/Chroma1-HD)
- [Guide Chroma (levzzz)](https://github.com/maybleMyers/chromaforge/blob/main/levzzz_chroma_guide.md)
