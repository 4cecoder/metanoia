.PHONY: dev test test-cov lint clean

dev:
	uv run python tools/tts_server.py

test:
	uv run pytest tests/ -v

test-cov:
	uv run pytest tests/ -v --cov=tools/metanoia_server --cov-report=term --cov-report=html

lint:
	uv run ruff check tools/metanoia_server/ tests/

clean:
	rm -rf cache/*
	rm -rf __pycache__ tools/metanoia_server/__pycache__ tools/metanoia_server/routes/__pycache__ tests/__pycache__
	rm -rf .coverage htmlcov
