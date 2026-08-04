#!/usr/bin/env python3
"""
End-to-End TTS Test: Generate audio with Qwen3-TTS and transcribe with Whisper.

This script tests the full pipeline:
1. Generate speech from text using Python TTS server (MLX backend)
2. Save audio to WAV file
3. Transcribe audio back to text using Whisper CLI
4. Compare transcription accuracy (word error rate, similarity)

Usage:
    python test_tts_transcription.py [--text "Your text here"] [--voice Vivian]
"""

import os
import sys
import subprocess
import json
import argparse
import tempfile
from pathlib import Path
from typing import Optional
from datetime import datetime

try:
    import requests
except ImportError:
    print("Installing requests...")
    subprocess.run([sys.executable, "-m", "pip", "install", "requests", "-q"], check=True)
    import requests


def start_tts_server() -> bool:
    """Start the TTS server if not already running."""
    try:
        response = requests.get("http://127.0.0.1:8000/system_info", timeout=2)
        print(f"✓ TTS server already running: {response.json()}")
        return True
    except requests.exceptions.ConnectionError:
        print("Starting TTS server...")
        server_proc = subprocess.Popen(
            [sys.executable, "tools/tts_server.py"],
            cwd="/home/fource/bytecats/projects/metanoia",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Wait for server to start
        import time
        for i in range(30):
            try:
                response = requests.get("http://127.0.0.1:8000/system_info", timeout=1)
                print(f"✓ TTS server started: {response.json()}")
                return True
            except requests.exceptions.ConnectionError:
                time.sleep(1)
        
        print("✗ Failed to start TTS server")
        return False


def generate_audio(text: str, voice: str = "Vivian", output_path: Optional[str] = None) -> Optional[str]:
    """Generate audio using TTS server."""
    print(f"\n🔊 Generating audio for: \"{text}\"")
    
    try:
        response = requests.post(
            "http://127.0.0.1:8000/generate",
            params={
                "text": text,
                "voice": voice,
                "mode": "speedy"
            },
            timeout=120
        )
        
        if response.status_code != 200:
            print(f"✗ TTS generation failed: {response.status_code}")
            return None
        
        audio_bytes = response.content
        
        if output_path is None:
            output_path = f"/tmp/tts_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}.wav"
        
        with open(output_path, "wb") as f:
            f.write(audio_bytes)
        
        # Get file info
        file_size = len(audio_bytes)
        duration_ms = file_size * 8 / (24000 * 16)  # 24kHz, 16-bit
        
        print(f"✓ Audio saved to: {output_path}")
        print(f"  Size: {file_size:,} bytes")
        print(f"  Duration: ~{duration_ms/1000:.2f}s")
        
        return output_path
    
    except requests.exceptions.Timeout:
        print("✗ TTS generation timed out")
        return None
    except Exception as e:
        print(f"✗ TTS generation error: {e}")
        return None


def transcribe_audio(audio_path: str) -> Optional[str]:
    """Transcribe audio using Whisper CLI."""
    print(f"\n🎤 Transcribing audio with Whisper...")
    
    try:
        # Run whisper-cli
        result = subprocess.run(
            [
                "/usr/bin/whisper-cli",
                "-ot", "0",  # no offset
                "-sow",      # split on word
                "-ml", "100",  # max segment length
                "-ac", "0",   # full audio context
                "-f",        # force output
                audio_path
            ],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode != 0:
            print(f"✗ Whisper failed: {result.stderr}")
            return None
        
        # Extract transcription from output
        # whisper-cli outputs in format: [00:00:00.000 --> 00:00:01.000]  text
        transcription = ""
        for line in result.stdout.strip().split('\n'):
            if '[' in line and ']' in line:
                # Extract text after the timestamp
                parts = line.split(']', 1)
                if len(parts) > 1:
                    transcription += parts[1].strip() + " "
        
        transcription = transcription.strip()
        
        print(f"✓ Transcription: \"{transcription}\"")
        return transcription
    
    except subprocess.TimeoutExpired:
        print("✗ Whisper transcribe timed out")
        return None
    except Exception as e:
        print(f"✗ Whisper error: {e}")
        return None


def calculate_word_error_rate(original: str, transcription: str) -> dict:
    """Calculate word error rate and similarity metrics."""
    # Normalize text: lowercase, remove punctuation
    def normalize(text):
        import re
        return re.sub(r'[^\w\s]', '', text.lower()).strip()
    
    orig_words = normalize(original).split()
    trans_words = normalize(transcription).split()
    
    # Simple WER calculation
    if len(orig_words) == 0:
        return {"wer": 1.0, "accuracy": 0.0, "word_match": 0, "word_total": 0}
    
    # Count matching words (position-aware for simplicity)
    matches = sum(1 for o, t in zip(orig_words, trans_words) if o == t)
    
    wer = 1.0 - (matches / len(orig_words))
    accuracy = (matches / len(orig_words)) * 100
    
    return {
        "wer": wer,
        "accuracy": accuracy,
        "word_match": matches,
        "word_total": len(orig_words),
        "orig_words": orig_words,
        "trans_words": trans_words
    }


def run_e2e_test(text: str, voice: str = "Vivian") -> dict:
    """Run complete end-to-end test."""
    print("=" * 60)
    print("🧪 End-to-End TTS Test with Whisper Verification")
    print("=" * 60)
    
    results = {
        "text": text,
        "voice": voice,
        "timestamp": datetime.now().isoformat(),
        "audio_path": None,
        "transcription": None,
        "metrics": None
    }
    
    # Step 1: Generate audio
    audio_path = generate_audio(text, voice)
    if not audio_path:
        results["error"] = "TTS generation failed"
        return results
    
    results["audio_path"] = audio_path
    
    # Step 2: Transcribe audio
    transcription = transcribe_audio(audio_path)
    if not transcription:
        results["error"] = "Whisper transcription failed"
        return results
    
    results["transcription"] = transcription
    
    # Step 3: Calculate metrics
    metrics = calculate_word_error_rate(text, transcription)
    results["metrics"] = metrics
    
    # Print results
    print("\n" + "=" * 60)
    print("📊 Test Results")
    print("=" * 60)
    print(f"Original text:    \"{text}\"")
    print(f"Transcription:   \"{transcription}\"")
    print(f"Word match:       {metrics['word_match']}/{metrics['word_total']} words")
    print(f"Accuracy:         {metrics['accuracy']:.1f}%")
    print(f"WER:              {metrics['wer']:.3f}")
    
    # Quality assessment
    if metrics['accuracy'] >= 80:
        print("\n✅ EXCELLENT: High speech clarity!")
    elif metrics['accuracy'] >= 50:
        print("\n⚠️  GOOD: Speech is intelligible but has some errors.")
    else:
        print("\n❌ POOR: Speech has significant errors.")
    
    print("=" * 60)
    
    return results


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
        "--batch",
        action="store_true",
        help="Run multiple test phrases"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="/tmp/tts_e2e_results.json",
        help="Output JSON file for results"
    )
    
    args = parser.parse_args()
    
    # Start TTS server
    if not start_tts_server():
        print("Cannot continue without TTS server")
        return 1
    
    # Run tests
    all_results = []
    
    if args.batch:
        # Run multiple test phrases
        test_phrases = [
            "For God so loved the world.",
            "The Lord is my shepherd.",
            "In the beginning God created the heavens and the earth.",
            "Be still and know that I am God.",
            "I am the way, the truth, and the life."
        ]
        
        for phrase in test_phrases:
            result = run_e2e_test(phrase, args.voice)
            all_results.append(result)
            print()
    else:
        # Run single test
        result = run_e2e_test(args.text, args.voice)
        all_results.append(result)
    
    # Save results
    with open(args.output, "w") as f:
        json.dump(all_results, f, indent=2)
    
    print(f"\n💾 Results saved to: {args.output}")
    
    # Summary
    if len(all_results) > 1:
        avg_accuracy = sum(r["metrics"]["accuracy"] for r in all_results if r["metrics"]) / len(all_results)
        print(f"📈 Average accuracy across {len(all_results)} tests: {avg_accuracy:.1f}%")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())