include .env

.DEFAULT_GOAL := help

# Optionally add the "-it" flag for docker run commands if the env var "CI" is not set (meaning we are on a local machine and not in github actions)
TTY_ARG :=
ifndef CI
	TTY_ARG := -it
endif

# Silent mode by default. Run `make VERBOSE=1` to turn off silent mode.
ifndef VERBOSE
.SILENT:
endif

# Idiomatic way to force a target to always run, by having it depend on this dummy target
FORCE:

.PHONY: help
help: ## Show a list of all targets
	grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/\1:\3/p' \
	| column -t -s ":"

.PHONY: _create-folders
_create-folders:
	mkdir -p .cache/docker
	mkdir -p .cache/pre-commit
	mkdir -p .cache/go
	mkdir -p .cache/go-build
	mkdir -p .cache/tmp
	mkdir -p .cache/.terraform.d/plugin-cache
	mkdir -p .cache/.zarf-cache

.PHONY: docker-save-build-harness
docker-save-build-harness: _create-folders ## Pulls the build harness docker image and saves it to a tarball
	docker pull ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}
	docker save -o .cache/docker/build-harness.tar ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION}

.PHONY: docker-load-build-harness
docker-load-build-harness: ## Loads the saved build harness docker image
	docker load -i .cache/docker/build-harness.tar

.PHONY: _runhooks
_runhooks: _create-folders
	docker run $(TTY_ARG) --rm \
		-v "${PWD}:/app" \
		-v "${PWD}/.cache/tmp:/tmp" \
		-v "${PWD}/.cache/go:/root/go" \
		-v "${PWD}/.cache/go-build:/root/.cache/go-build" \
		-v "${PWD}/.cache/.terraform.d/plugin-cache:/root/.terraform.d/plugin-cache" \
		-v "${PWD}/.cache/.zarf-cache:/root/.zarf-cache" \
		--workdir "/app" \
		-e GOPATH=/root/go \
		-e GOCACHE=/root/.cache/go-build \
		-e TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
		-e TF_PLUGIN_CACHE_DIR=/root/.terraform.d/plugin-cache \
		-e "SKIP=$(SKIP)" \
		-e "PRE_COMMIT_HOME=/app/.cache/pre-commit" \
		${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION} \
		bash -c 'git config --global --add safe.directory /app && asdf install && pre-commit run -a --show-diff-on-failure $(HOOK)'

.PHONY: pre-commit-all
pre-commit-all: ## Run all pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP=""

.PHONY: pre-commit-terraform
pre-commit-terraform: ## Run the terraform pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,go-fmt,golangci-lint,renovate-config-validator"

.PHONY: pre-commit-golang
pre-commit-golang: ## Run the golang pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="check-added-large-files,check-merge-conflict,detect-aws-credentials,detect-private-key,end-of-file-fixer,fix-byte-order-marker,trailing-whitespace,check-yaml,fix-smartquotes,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: pre-commit-renovate
pre-commit-renovate: ## Run the renovate pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="renovate-config-validator" SKIP=""

.PHONY: pre-commit-common
pre-commit-common: ## Run the common pre-commit hooks. Returns nonzero exit code if any hooks fail. Uses Docker for maximum compatibility
	$(MAKE) _runhooks HOOK="" SKIP="go-fmt,golangci-lint,terraform_fmt,terraform_docs,terraform_checkov,terraform_tflint,renovate-config-validator"

.PHONY: fix-cache-permissions
fix-cache-permissions: ## Fixes the permissions on the pre-commit cache
	docker run $(TTY_ARG) --rm -v "${PWD}:/app" --workdir "/app" -e "PRE_COMMIT_HOME=/app/.cache/pre-commit" ${BUILD_HARNESS_REPO}:${BUILD_HARNESS_VERSION} chmod -R a+rx .cache
