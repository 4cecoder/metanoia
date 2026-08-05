#!/usr/bin/env python3
"""
End-to-End TTS Test with Whisper Verification.

Uses faster_whisper (same as TTS server) for transcription.

Usage:
    uv run tools/test_tts_e2e.py --text "Your text here"
"""

import os
import sys
import argparse
import tempfile
from pathlib import Path
from typing import Optional, Tuple
from datetime import datetime

# Import with uv
import requests
from faster_whisper import WhisperModel


def generate_audio(text: str, voice: str = "Vivian") -> Tuple[Optional[bytes], Optional[dict]]:
    """Generate audio using TTS server."""
    print(f"\n🔊 Generating audio for: \"{text}\"")
    
    try:
        response = requests.post(
            "http://127.0.0.1:8000/generate",
            json={
                "text": text,
                "voice": voice,
                "mode": "speedy",
                "speed": 1.0,
                "temperature": 0.5,
                "cfg_scale": 2.0,
                "force_refresh": False
            },
            timeout=120
        )
        
        if response.status_code != 200:
            print(f"✗ TTS generation failed: {response.status_code}")
            print(f"  Response: {response.text[:200]}")
            return None, None
        
        audio_bytes = response.content
        
        # Get file info
        file_size = len(audio_bytes)
        # Assume 24kHz, 16-bit, mono (WAV format)
        duration_ms = file_size * 8 / (24000 * 16)
        
        print(f"✓ Audio generated successfully")
        print(f"  Size: {file_size:,} bytes")
        print(f"  Duration: ~{duration_ms/1000:.2f}s")
        
        return audio_bytes, {"size": file_size, "duration_ms": duration_ms}
    
    except requests.exceptions.Timeout:
        print("✗ TTS generation timed out")
        return None, None
    except requests.exceptions.ConnectionError:
        print("✗ Cannot connect to TTS server (is it running on port 8000?)")
        return None, None
    except Exception as e:
        print(f"✗ TTS generation error: {e}")
        return None, None


def transcribe_audio(audio_bytes: bytes, model_size: str = "tiny") -> Optional[dict]:
    """Transcribe audio using faster_whisper."""
    print(f"\n🎤 Transcribing with faster_whisper ({model_size} model)...")
    
    try:
        # Load model
        model = WhisperModel(model_size, device="cpu", compute_type="int8")
        
        # Write to temp file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(audio_bytes)
            temp_path = f.name
        
        try:
            # Transcribe
            segments, info = model.transcribe(
                temp_path,
                beam_size=5,
                language="en",
                vad_filter=True,
                word_timestamps=True
            )
            
            # Collect segments
            transcription_text = " ".join(segment.text for segment in segments).strip()
            
            # Get detailed info
            result = {
                "text": transcription_text,
                "language": info.language,
                "language_probability": info.language_probability,
                "duration": info.duration,
                "segments": [
                    {
                        "text": segment.text.strip(),
                        "start": segment.start,
                        "end": segment.end,
                        "words": segment.words if hasattr(segment, 'words') else []
                    }
                    for segment in segments
                ]
            }
            
            print(f"✓ Transcription complete")
            print(f"  Language: {info.language} (confidence: {info.language_probability:.2%})")
            print(f"  Duration: {info.duration:.2f}s")
            print(f"  Text: \"{transcription_text}\"")
            
            return result
        
        finally:
            # Cleanup temp file
            Path(temp_path).unlink(missing_ok=True)
    
    except Exception as e:
        print(f"✗ Whisper transcription error: {e}")
        return None


def calculate_metrics(original: str, transcription: str) -> dict:
    """Calculate word error rate and similarity metrics."""
    import re
    
    def normalize(text):
        """Normalize text: lowercase, remove punctuation, normalize whitespace."""
        text = text.lower()
        text = re.sub(r'[^\w\s]', '', text)
        text = re.sub(r'\s+', ' ', text).strip()
        return text
    
    orig_words = normalize(original).split()
    trans_words = normalize(transcription).split()
    
    if len(orig_words) == 0:
        return {"wer": 1.0, "accuracy": 0.0, "word_match": 0, "word_total": 0, "orig": [], "trans": []}
    
    # Simple word-level alignment (position-based for simplicity)
    max_len = max(len(orig_words), len(trans_words))
    orig_padded = orig_words + [""] * (max_len - len(orig_words))
    trans_padded = trans_words + [""] * (max_len - len(trans_words))
    
    matches = sum(1 for o, t in zip(orig_padded, trans_padded) if o == t)
    
    # Calculate metrics
    wer = 1.0 - (matches / len(orig_words)) if len(orig_words) > 0 else 1.0
    accuracy = (matches / len(orig_words)) * 100 if len(orig_words) > 0 else 0.0
    
    # Levenshtein-like edit distance
    insertions = max(0, len(trans_words) - len(orig_words))
    deletions = max(0, len(orig_words) - len(trans_words))
    substitutions = len(orig_words) - matches + deletions
    
    return {
        "wer": wer,
        "accuracy": accuracy,
        "word_match": matches,
        "word_total": len(orig_words),
        "trans_word_count": len(trans_words),
        "insertions": insertions,
        "deletions": deletions,
        "substitutions": substitutions,
        "orig_words": orig_words,
        "trans_words": trans_words
    }


def print_results(text: str, transcription: dict, metrics: dict, audio_info: dict):
    """Print detailed test results."""
    print("\n" + "=" * 70)
    print("📊 Test Results")
    print("=" * 70)
    
    print(f"\n📝 Original Text:")
    print(f"  \"{text}\"")
    
    print(f"\n🎤 Transcription:")
    print(f"  \"{transcription['text']}\"")
    
    print(f"\n📏 Audio Info:")
    print(f"  Size: {audio_info['size']:,} bytes")
    print(f"  Duration: ~{audio_info['duration_ms']/1000:.2f}s")
    print(f"  Sample Rate: ~24kHz (inferred)")
    
    print(f"\n🔍 Transcription Details:")
    print(f"  Language: {transcription['language']} (confidence: {transcription['language_probability']:.2%})")
    print(f"  Duration: {transcription['duration']:.2f}s")
    print(f"  Segments: {len(transcription['segments'])}")
    
    print(f"\n📈 Accuracy Metrics:")
    print(f"  Word Match: {metrics['word_match']}/{metrics['word_total']} words")
    print(f"  Accuracy:   {metrics['accuracy']:.1f}%")
    print(f"  WER:        {metrics['wer']:.3f}")
    print(f"  Edit Distance:")
    print(f"    Insertions:    {metrics['insertions']}")
    print(f"    Deletions:     {metrics['deletions']}")
    print(f"    Substitutions: {metrics['substitutions']}")
    
    print(f"\n🔤 Word-Level Comparison:")
    print(f"  Original:  {metrics['orig_words']}")
    print(f"  Transcribed: {metrics['trans_words']}")
    
    print(f"\n" + "=" * 70)
    
    # Quality assessment
    if metrics['accuracy'] >= 90:
        print("✅ EXCELLENT: Near-perfect speech clarity!")
    elif metrics['accuracy'] >= 70:
        print("✅ GOOD: Speech is very intelligible with minor errors.")
    elif metrics['accuracy'] >= 50:
        print("⚠️  FAIR: Speech is understandable but has noticeable errors.")
    else:
        print("❌ POOR: Speech has significant transcription errors.")
    
    print("=" * 70 + "\n")


def run_e2e_test(text: str, voice: str = "Vivian", model_size: str = "tiny") -> dict:
    """Run complete end-to-end test."""
    print("\n" + "=" * 70)
    print("🧪 End-to-End TTS Test with Whisper Verification")
    print("=" * 70)
    print(f"📅 Timestamp: {datetime.now().isoformat()}")
    print(f"🎭 Voice: {voice}")
    print(f"🤖 Whisper Model: {model_size}")
    
    result = {
        "timestamp": datetime.now().isoformat(),
        "text": text,
        "voice": voice,
        "whisper_model": model_size,
        "success": False,
        "error": None,
        "audio": None,
        "transcription": None,
        "metrics": None
    }
    
    # Step 1: Generate audio
    audio_bytes, audio_info = generate_audio(text, voice)
    if not audio_bytes:
        result["error"] = "TTS generation failed"
        return result
    
    result["audio"] = audio_info or {}
    
    # Step 2: Transcribe audio
    transcription = transcribe_audio(audio_bytes, model_size)
    if not transcription:
        result["error"] = "Whisper transcription failed"
        return result
    
    result["transcription"] = transcription
    
    # Step 3: Calculate metrics
    metrics = calculate_metrics(text, transcription["text"])
    result["metrics"] = metrics
    result["success"] = True
    
    # Print results
    print_results(text, transcription, metrics, result["audio"])
    
    return result


def main():
    parser = argparse.ArgumentParser(
        description="End-to-end TTS test with Whisper verification"
    )
    parser.add_argument(
        "--text",
        type=str,
        default="For God so loved the world that he gave his only Son.",
        help="Text to synthesize"
    )
    parser.add_argument(
        "--voice",
        type=str,
        default="Vivian",
        help="Voice to use for synthesis"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="tiny",
        choices=["tiny", "base", "small", "medium", "large"],
        help="Whisper model size (tiny=fastest, large=most accurate)"
    )
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Run multiple test phrases"
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output JSON file for results (default: don't save)"
    )
    
    args = parser.parse_args()
    
    # Check server connectivity
    try:
        response = requests.get("http://127.0.0.1:8000/system_info", timeout=30)
        print(f"✓ Connected to TTS server")
    except requests.exceptions.ConnectionError:
        print("✗ Cannot connect to TTS server on http://127.0.0.1:8000")
        print("  Please start the server first: uv run tools/tts_server.py")
        return 1
    except requests.exceptions.Timeout:
        print("⚠️  Server slow to respond, but proceeding...")
    
    # Run tests
    all_results = []
    
    if args.batch:
        # Run multiple test phrases (biblical references)
        test_phrases = [
            "For God so loved the world.",
            "The Lord is my shepherd, I shall not want.",
            "In the beginning, God created the heavens and the earth.",
            "Be still and know that I am God.",
            "I am the way, the truth, and the life."
        ]
        
        for i, phrase in enumerate(test_phrases, 1):
            print(f"\n{'#' * 70}")
            print(f"# Test {i}/{len(test_phrases)}")
            print(f"{'#' * 70}")
            
            result = run_e2e_test(phrase, args.voice, args.model)
            all_results.append(result)
            
            # Auto-continue after a short pause
            if i < len(test_phrases):
                print(f"\n⏱️  Waiting 2s before next test...")
                import time
                time.sleep(2)
    else:
        # Run single test
        result = run_e2e_test(args.text, args.voice, args.model)
        all_results.append(result)
    
    # Save results if requested
    if args.output:
        import json
        with open(args.output, "w") as f:
            json.dump(all_results, f, indent=2)
        print(f"💾 Results saved to: {args.output}")
    
    # Summary
    if len(all_results) > 1:
        successful = sum(1 for r in all_results if r["success"])
        avg_accuracy = sum(r["metrics"]["accuracy"] for r in all_results if r["metrics"]) / len(all_results)
        
        print("\n" + "=" * 70)
        print("📈 Batch Test Summary")
        print("=" * 70)
        print(f"Tests run:    {len(all_results)}")
        print(f"Successful:   {successful}/{len(all_results)}")
        print(f"Avg accuracy: {avg_accuracy:.1f}%")
        print("=" * 70)
    
    return 0 if all(r["success"] for r in all_results) else 1


if __name__ == "__main__":
    sys.exit(main())