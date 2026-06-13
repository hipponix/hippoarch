# HippoArch QA Makefile

.PHONY: help lint security test-syntax install-deps

help:
	@echo "HippoArch QA Tools"
	@echo "Usage:"
	@echo "  make install-deps  - Install shellcheck + configure git hooks"
	@echo "  make lint          - Run shellcheck on all scripts"
	@echo "  make security      - Scan for sensitive patterns"
	@echo "  make test-syntax   - Bash syntax check (bash -n)"

install-deps:
	@echo "Detecting package manager..."
	@if [ -f /usr/bin/pacman ]; then \
		sudo pacman -S --needed --noconfirm shellcheck; \
	elif [ -f /usr/bin/apt ]; then \
		sudo apt-get update && sudo apt-get install -y shellcheck; \
	else \
		echo "Unsupported package manager. Install 'shellcheck' manually."; \
		exit 1; \
	fi
	@git config core.hooksPath hooks
	@echo "Git hooks configured (hooks/ -> .git/hooks)."

lint:
	@shellcheck bootstrap.sh provision.sh common/base.sh lib/partition.sh \
		roles/server/install.sh roles/workstation/install.sh

security:
	@echo "Checking for sensitive patterns..."
	@grep -rEi "PASSWORD|SECRET|KEY|TOKEN" . \
		--exclude-dir=.git --exclude=Makefile --exclude="*.conf" \
		|| echo "No sensitive keywords found."

test-syntax:
	@bash -n bootstrap.sh
	@bash -n provision.sh
	@bash -n common/base.sh
	@bash -n lib/partition.sh
	@echo "Syntax OK."
