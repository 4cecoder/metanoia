import sys
import types


def test_mlx_startup_preloads_only_speedy(monkeypatch):
    from tools.metanoia_server import engine_loader

    calls = []

    class FakeMLXEngine:
        def load_models(self, mode=None):
            calls.append(mode)

    fake_module = types.ModuleType("mlx_engine")
    fake_module.MLXEngine = FakeMLXEngine
    monkeypatch.setitem(sys.modules, "mlx_engine", fake_module)

    container = engine_loader.EngineContainer()
    engine = engine_loader._load_mlx_engine(container, {})

    assert engine is container.mlx_engine
    assert calls == ["speedy"]


def test_startup_warms_only_speedy_cloned_voices(tmp_path):
    from tools.metanoia_server import engine_loader

    speedy_audio = tmp_path / "jordan.wav"
    gold_audio = tmp_path / "mari.wav"
    speedy_audio.touch()
    gold_audio.touch()

    calls = []

    class FakeEngine:
        def precompute_voice_prompt(self, **kwargs):
            calls.append(kwargs)

    voices = {
        "jordan": {
            "audio": str(speedy_audio),
            "text": "reference",
            "mode": "speedy",
        },
        "mari": {
            "audio": str(gold_audio),
            "text": "reference",
            "mode": "gold",
        },
        "vivian": {"audio": None, "text": None, "mode": "custom"},
    }

    engine_loader._precompute_prompts(FakeEngine(), voices)

    assert [call["name"] for call in calls] == ["jordan"]
    assert calls[0]["mode"] == "speedy"


def test_mlx_prompt_fast_path_reuses_reference_conditioning():
    from tools.mlx_engine import MLXEngine

    class FakeTokenizer:
        def encode(self, audio):
            raise AssertionError("reference audio should be served from cache")

    class FakeModel:
        speech_tokenizer = FakeTokenizer()
        speaker_encoder = object()

        def extract_speaker_embedding(self, audio, sr=24000):
            raise AssertionError("speaker embedding should be served from cache")

    engine = MLXEngine()
    model = FakeModel()
    engine._install_prompt_fast_paths(model)
    engine._prompt_context.value = {
        "ref_codes": "cached-codes",
        "speaker_embed": "cached-speaker",
    }

    assert model.speech_tokenizer.encode("audio") == "cached-codes"
    assert model.extract_speaker_embedding("audio") == "cached-speaker"
