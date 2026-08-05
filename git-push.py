#!/usr/bin/env python3
import subprocess
import os

os.chdir('/Users/fource/bytecats/metanoia')
subprocess.run(['git', 'add', '.well-known/assetlinks.json', '.github/workflows/pages.yml'])
subprocess.run(['git', 'commit', '-m', 'feat: add GitHub Pages for Android App Links verification'])
subprocess.run(['git', 'push', 'origin', 'master'])
