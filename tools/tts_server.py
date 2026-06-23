import uvicorn
import os
import sys

# Ensure the tools directory is in path
tools_dir = os.path.dirname(os.path.abspath(__file__))
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

if __name__ == "__main__":
    print("Launching Modular Metanoia Neural Engine...")
    uvicorn.run("metanoia_server.main:app", host="0.0.0.0", port=8000, reload=True, reload_dirs=[tools_dir])
