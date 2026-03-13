SHELL := /bin/bash
ROOT_DIR := $(shell pwd)

.PHONY: bootstrap lint test validate deploy destroy backup restore fmt smoke

bootstrap:
	./scripts/bootstrap.sh

lint:
	./scripts/bootstrap.sh
	if command -v shellcheck >/dev/null 2>&1; then shellcheck scripts/*.sh tests/*.sh; else echo "shellcheck not installed"; fi
	if command -v yamllint >/dev/null 2>&1; then yamllint .github/workflows infra/ansible; else echo "yamllint not installed"; fi
	if command -v markdownlint >/dev/null 2>&1; then find . -path './infra/tofu/.terraform' -prune -o -name '*.md' -print0 | xargs -0 markdownlint; else echo "markdownlint not installed"; fi
	if command -v tflint >/dev/null 2>&1; then (cd infra/tofu && tflint --init && tflint); else echo "tflint not installed"; fi

fmt:
	if command -v tofu >/dev/null 2>&1; then (cd infra/tofu && tofu fmt -recursive); fi

validate:
	./tests/infra-tests.sh

test:
	./tests/infra-tests.sh
	./tests/security-tests.sh
	./tests/deployment-tests.sh

smoke:
	./scripts/smoke-openbao.sh

deploy:
	./scripts/deploy.sh

destroy:
	./scripts/destroy.sh

backup:
	./scripts/backup.sh

restore:
	./scripts/restore.sh $(ARCHIVE)
