#!/bin/bash
cd /Users/fource/bytecats/metanoia
git add .well-known/assetlinks.json .github/workflows/pages.yml
git commit -m "feat: add GitHub Pages for Android App Links verification"
git push origin master
