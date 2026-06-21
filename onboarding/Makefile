# Makefile for the incrementalmerkletree onboarding course (Docusaurus 3).
# Wrap recipes with tabs; keep lines within 80 columns.

.PHONY: help
help: ## Ask for help!
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install Node dependencies
	npm install

.PHONY: dev
dev: ## Run the Docusaurus dev server
	npx docusaurus start

.PHONY: build
build: ## Build the static site
	npx docusaurus build

.PHONY: preview
preview: ## Serve the built static site
	npx docusaurus serve

.PHONY: check-format
check-format: ## Check Markdown/TS formatting
	npx prettier --check .

.PHONY: format
format: ## Format Markdown/TS sources
	npx prettier --write .

.PHONY: clean-doc
clean-doc: ## Remove build artefacts (keeps node_modules)
	npx docusaurus clear
	rm -rf build .docusaurus
	rm -rf ../404.html ../index.html ../sitemap.xml \
		../search-index.json ../.nojekyll ../assets ../img

.PHONY: clean
clean: clean-doc ## Remove build artefacts and node_modules
	rm -rf node_modules
