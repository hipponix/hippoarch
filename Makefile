# HippoArch QA Makefile

.PHONY: help lint security test install-deps

help:
	@echo "HippoArch QA Tools"
	@echo "Usage:"
	@echo "  make install-deps - Install shellcheck and docker"
	@echo "  make lint         - Check scripts for syntax errors (shellcheck)"
	@echo "  make security     - Run security audits (shfmt / basic grep)"
	@echo "  make test         - Run unit tests (mock environment)"

install-deps:
	@echo "Detecting package manager..."
	@if [ -f /usr/bin/pacman ]; then \
		sudo pacman -S --needed --noconfirm shellcheck docker; \
	elif [ -f /usr/bin/apt ]; then \
		sudo apt update && sudo apt install -y shellcheck docker.io; \
	else \
		echo "Unsupported package manager. Please install 'shellcheck' and 'docker' manually."; \
		exit 1; \
	fi
	@sudo systemctl enable --now docker || true
	@sudo usermod -aG docker $$(whoami) || true
	@echo "Dependencies installed. Please logout and login again if this is your first time installing Docker."

lint:
	@echo "Running ShellCheck..."
	@docker run --rm -v "$$(pwd):/mnt" koalaman/shellcheck:stable \
		bootstrap.sh \
		provision.sh \
		common/base.sh \
		lib/partition.sh \
		roles/server/install.sh \
		roles/workstation/install.sh

security:
	@echo "Checking for sensitive patterns..."
	@grep -rE "PASSWORD|SECRET|KEY|TOKEN" . --exclude-dir=.git --exclude=Makefile || echo "No sensitive keywords found (basic check)."

test:
	@echo "Running Unit Tests (Syntax check only for now)..."
	@bash -n bootstrap.sh
	@bash -n provision.sh
	@bash -n common/base.sh
	@echo "Tests passed (Syntax OK)."
