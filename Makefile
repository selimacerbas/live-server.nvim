.PHONY: help test
help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## / : /'

test: ## Run every headless suite and the help-tags check (tests/run.sh)
	bash tests/run.sh
