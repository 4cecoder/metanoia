.PHONY: dev test test-cov lint fmt build app icon clean crosscheck windows-vm windows-build all

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

check: crosscheck test-zig test lint

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

# --- Windows Dev Cycle ---

crosscheck:
	docker build -t metanoia-crosscheck -f ci/Dockerfile.crosscheck . && \
	docker run --rm -v "$(PWD):/workspace" metanoia-crosscheck

windows-vm:
	@if docker inspect metanoia-windows >/dev/null 2>&1; then \
		echo "Starting existing container metanoia-windows..."; \
		docker start metanoia-windows 2>/dev/null || true; \
	else \
		echo "Creating new Windows VM container..."; \
		docker volume create windows-data 2>/dev/null || true; \
		docker run -d --name metanoia-windows \
			--device /dev/kvm \
			--cap-add NET_ADMIN \
			-p 8006:8006 -p 3389:3389 \
			-v windows-data:/storage \
			-v "$(PWD)/ci/win-build.ps1:/storage/win-build.ps1" \
			-e VERSION=11 \
			-e RAM_SIZE=4G \
			-e CPU_CORES=2 \
			-e DISK_SIZE=40G \
			-e USERNAME=metanoia \
			-e PASSWORD=metanoia \
			dockurr/windows; \
	fi

windows-build: windows-vm
	docker cp ci/win-build.ps1 metanoia-windows:/storage/win-build.ps1 2>/dev/null || true
	@echo "=== Executing Windows build ==="
	-docker exec metanoia-windows powershell -File C:/storage/win-build.ps1

all: check build test
