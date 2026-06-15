TOMLENV_SOURCE_DIR=tomlenv
TOMLENV_TARGET_BINARY_RELATIVE_PATH=bin/tomlenv
TOMLENV_TARGET_BINARY=${TOMLENV_SOURCE_DIR}/${TOMLENV_TARGET_BINARY_RELATIVE_PATH}
TOMLENV_SOURCE_FILES=$(shell find ${TOMLENV_SOURCE_DIR} -name *.go)
TOMLENV_MODULE_FILES=${TOMLENV_SOURCE_DIR}/go.mod ${TOMLENV_SOURCE_DIR}/go.sum

IMAGE_TAG=latest
IMAGE=benchmark:${IMAGE_TAG}

start: docker-build
	docker run -it --rm -v $(HOME)/.kube:/root/.kube -v $(HOME)/.aws:/root/.aws -v $(PWD):/workspace ${IMAGE}

.PHONY: check
check: tomlenv
	@./tests/checks.sh

.PHONY: tomlenv
tomlenv: ${TOMLENV_TARGET_BINARY}
	 @${TOMLENV_TARGET_BINARY} env.toml > last.run

.PHONY: shellcheck
shellcheck:
	@bash -c 'files=$$(git ls-files "*.sh"); \
		if command -v shellcheck >/dev/null 2>&1; then \
			shellcheck -x -e SC1091 -s bash $$files; \
		elif command -v docker >/dev/null 2>&1; then \
			docker run --rm -v "$$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x -e SC1091 -s bash $$files; \
		else \
			echo "shellcheck is required; install shellcheck or Docker."; \
			exit 127; \
		fi'

${TOMLENV_TARGET_BINARY}: $(TOMLENV_SOURCE_FILES) $(TOMLENV_MODULE_FILES)
	@cd ${TOMLENV_SOURCE_DIR} && go build -o ${TOMLENV_TARGET_BINARY_RELATIVE_PATH} main.go

.PHONY: docker-build
docker-build:
	docker build -t ${IMAGE} -f Dockerfile . --load
