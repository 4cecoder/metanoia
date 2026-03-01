#!/bin/bash

# Configuration
BRANCH="master"
SERVER_SCRIPT="tools/tts_server.py"
PORT=8000
HOST="127.0.0.1"

echo "--- Metanoia TTS Server Auto-Updater ---"

# Function to check for updates
check_updates() {
    echo "Checking for updates on $BRANCH..."
    git fetch origin $BRANCH
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/$BRANCH)

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "Updates detected! Pulling changes..."
        git pull origin $BRANCH
        echo "Updating dependencies (if any)..."
        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt
        elif [ -f "pyproject.toml" ]; then
            pip install .
        fi
        return 0 # Updated
    else
        echo "Already up to date."
        return 1 # No update
    fi
}

# Initial check
check_updates

# Start the server with uvicorn --reload
# Note: --reload watches for local file changes and restarts the worker.
# We will run a background loop to check for git updates as well.

echo "Starting TTS Server on $HOST:$PORT with autoreload..."

# Background loop for git polling (every 60 seconds)
(
    while true; do
        sleep 60
        if check_updates; then
            echo "Git changes pulled. Uvicorn --reload should pick up the changes if tools/tts_server.py was modified."
        fi
    done
) &

POLLER_PID=$!

# Trap to kill the poller on exit
trap "kill $POLLER_PID" EXIT

# Run uvicorn
python3 -m uvicorn tools.tts_server:app --host $HOST --port $PORT --reload --reload-dir tools
