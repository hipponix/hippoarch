# HippoArch QA Makefile

SHELL := /bin/bash

.PHONY: help lint security test test-unit test-functional test-syntax test-integration install-deps \
        release

VERSION  := $(shell cat VERSION)
HEADLESS ?= 0

help:
	@echo "HippoArch QA Tools"
	@echo "Usage:"
	@echo "  make install-deps      - Install shellcheck, docker, qemu, expect + configure git hooks"
	@echo "  make lint              - Run shellcheck on all scripts"
	@echo "  make security          - Scan for sensitive patterns"
	@echo "  make test-unit         - Run unit tests (bats + mocks, docker)"
	@echo "  make test-functional   - Run functional tests (real loopback devices, privileged docker)"
	@echo "  make test              - Run unit + functional tests"
	@echo "  make test-syntax       - Bash syntax check (bash -n)"
	@echo "  make test-integration  - Run QEMU integration test (HEADLESS=1 for headless)"
	@echo "  make release           - Tag and push v$(VERSION), triggering the release pipeline"

install-deps:
	@echo "Detecting package manager..."
	@if [ -f /usr/bin/pacman ]; then \
		sudo pacman -S --needed --noconfirm shellcheck docker \
			qemu-system-x86 qemu-img libarchive expect sshpass ovmf; \
	elif [ -f /usr/bin/apt ]; then \
		sudo apt-get update && sudo apt-get install -y shellcheck \
			qemu-system-x86 qemu-utils libarchive-tools expect sshpass ovmf; \
		command -v docker >/dev/null 2>&1 || sudo apt-get install -y docker.io; \
	else \
		echo "Unsupported package manager. Install dependencies manually."; \
		exit 1; \
	fi
	@sudo systemctl enable --now docker || true
	@sudo usermod -aG docker $$(whoami) || true
	@git config core.hooksPath hooks
	@echo "Git hooks configured (hooks/ -> .git/hooks)."

test-unit:
	@docker run --rm -v "$$(pwd):/hippoarch" -w /hippoarch bats/bats:1.11.0 tests/

test-functional:
	@docker run --rm --privileged \
		-v "$$(pwd):/hippoarch" -w /hippoarch \
		--entrypoint sh bats/bats:1.11.0 \
		-c "apk add -q --update --no-progress sgdisk dosfstools e2fsprogs btrfs-progs util-linux >/dev/null && \
		    bats tests/functional/"

test: test-unit test-functional

test-integration:
	@rm -f tests/integration/logs/*
	@HIPPOARCH_HEADLESS=$${HIPPOARCH_HEADLESS:-$(HEADLESS)} bash tests/integration/run.sh

lint:
	@shellcheck bootstrap.sh provision.sh common/base.sh lib/partition.sh \
		roles/server-cwwk/install.sh roles/workstation/install.sh

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

# ── Release ───────────────────────────────────────────────────────────────────

release:
	@set -e; \
	git diff --quiet HEAD || { echo "Error: uncommitted changes — commit first"; exit 1; }; \
	if git tag -l "v$(VERSION)" | grep -q . || \
	   git ls-remote --tags origin "refs/tags/v$(VERSION)" | grep -q .; then \
	    echo "Error: tag v$(VERSION) already exists — bump VERSION first"; exit 1; \
	fi; \
	latest=$$(git tag --sort=-v:refname | head -1); \
	branch=$$(git branch --show-current); \
	echo "Branch:             $$branch"; \
	echo "Current latest tag: $${latest:-none}"; \
	echo "New release:        v$(VERSION)"; \
	read -rp "Confirm? [y/N] " ans; \
	[[ "$$ans" == "y" || "$$ans" == "Y" ]] || { echo "Aborted."; exit 1; }; \
	[[ "$$branch" != "main" ]] || { echo "Error: run make release from a release branch, not main"; exit 1; }; \
	echo "Merging $$branch → main..."; \
	git checkout main; \
	git pull origin main; \
	git merge --no-ff "$$branch" -m "release: merge $$branch for v$(VERSION)"; \
	git push origin main; \
	echo "Tagging v$(VERSION)..."; \
	git tag "v$(VERSION)"; \
	git push origin "v$(VERSION)"; \
	echo "Pipeline: https://github.com/hipponix/hippoarch/actions"
