import os
from huggingface_hub import snapshot_download

MODELS = {
    "Base-bf16": "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16",
    "CustomVoice-8bit": "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
}

def download_models():
    os.makedirs("models", exist_ok=True)
    for name, repo in MODELS.items():
        print(f"Downloading {name} from {repo}...")
        local_dir = os.path.join("models", repo.split('/')[-1])
        snapshot_download(repo_id=repo, local_dir=local_dir)
        print(f"Done: {local_dir}")

if __name__ == "__main__":
    download_models()
