import os
import torch
from qwen_tts import Qwen3TTSModel
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("convert-qwen")

def convert_to_onnx():
    model_id = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
    output_dir = "mobile_tts/app/src/main/assets/models"
    os.makedirs(output_dir, exist_ok=True)
    
    onnx_path = os.path.join(output_dir, "qwen3_tts_0.6b_backbone.onnx")

    logger.info(f"Loading model: {model_id}")
    wrapper = Qwen3TTSModel.from_pretrained(
        model_id,
        device_map="cpu",
        dtype=torch.float32
    )
    
    talker = wrapper.model.talker
    hidden_size = talker.config.hidden_size # 1024
    
    class TalkerExportWrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m
        def forward(self, input_ids, past_hidden):
            # Pass mandatory tensors to avoid NoneType concatenation errors
            outputs = self.m(
                input_ids=input_ids, 
                past_hidden=past_hidden,
                return_dict=True
            )
            return outputs.logits

    model_to_export = TalkerExportWrapper(talker)
    model_to_export.eval()

    logger.info("Preparing dummy inputs (with past_hidden) for direct export...")
    dummy_input_ids = torch.randint(0, 3000, (1, 8)).long()
    dummy_past_hidden = torch.zeros(1, 1, hidden_size)
    
    logger.info(f"Exporting talker directly to ONNX: {onnx_path}")
    try:
        # Avoid JIT trace and go straight to ONNX export with legacy engine
        torch.onnx.export(
            model_to_export,
            (dummy_input_ids, dummy_past_hidden),
            onnx_path,
            export_params=True,
            opset_version=18,
            do_constant_folding=True,
            input_names=["input_ids", "past_hidden"],
            output_names=["logits"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "sequence"},
                "past_hidden": {0: "batch", 1: "sequence"},
                "logits": {0: "batch", 1: "sequence"}
            },
            dynamo=False
        )
        logger.info("ONNX Export Successful.")
    except Exception as e:
        logger.error(f"Talker Direct ONNX Export Failed: {e}")

if __name__ == "__main__":
    convert_to_onnx()
