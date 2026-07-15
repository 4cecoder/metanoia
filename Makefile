.PHONY: dev test test-cov lint fmt build app icon clean

# --- Development ---

dev:
	uv run python tools/tts_server.py

icon:
	python tools/gen_icon.py

# --- Build ---

build:
	zig build

app:
	zig build app

# --- Testing ---

test:
	uv run pytest tests/ -v

test-cov:
	uv run pytest tests/ -v --cov=tools/metanoia_server --cov-report=term --cov-report=html

test-zig:
	zig build test

check: test-zig test lint

# --- Quality ---

lint:
	uv run ruff check tools/metanoia_server/ tests/

fmt:
	uv run ruff format tools/metanoia_server/ tests/

# --- Cleanup ---

clean:
	rm -rf cache/*
	rm -rf __pycache__ tools/metanoia_server/__pycache__ tools/metanoia_server/routes/__pycache__ tests/__pycache__
	rm -rf .coverage htmlcov
	rm -rf zig-out
