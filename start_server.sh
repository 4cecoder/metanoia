#!/bin/bash
cd /home/cyber/dev/metanoia
export CUDA_HOME=/usr/local/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
export ORT_LOGGING_LEVEL=3
.venv/bin/python tools/tts_server.py
