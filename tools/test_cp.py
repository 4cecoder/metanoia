import onnxruntime as ort
import numpy as np

def test_cp():
    model_path = 'mobile_tts/models/code_predictor.onnx'
    print(f"Loading {model_path}")
    sess = ort.InferenceSession(model_path)
    
    # Standard Qwen3 shapes
    inputs = {
        'inputs_embeds': np.zeros((1, 1, 1024), dtype=np.float32),
        'generation_steps': np.array([0], dtype=np.int64),
        'past_keys': np.zeros((5, 1, 8, 0, 128), dtype=np.float32),
        'past_values': np.zeros((5, 1, 8, 0, 128), dtype=np.float32)
    }
    
    print("Testing with 1024-dim Float32...")
    try:
        sess.run(None, inputs)
        print("SUCCESS: 1024-dim Float32 works.")
    except Exception as e:
        print(f"FAILED: {e}")

    # Test 512-dim
    print("\nTesting with 512-dim Float32...")
    inputs['inputs_embeds'] = np.zeros((1, 1, 512), dtype=np.float32)
    try:
        sess.run(None, inputs)
        print("SUCCESS: 512-dim Float32 works.")
    except Exception as e:
        print(f"FAILED: {e}")

if __name__ == "__main__":
    test_cp()
