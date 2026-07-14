# n8n-hardened-reference - operations
SHELL := /usr/bin/env bash
COMPOSE := docker compose
.DEFAULT_GOAL := help
.PHONY: help init-secrets deploy deploy-runners up down restart ps logs backup restore pin-digests

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /  ->  /' | sort

init-secrets: ## Generate secrets/*.txt if absent
	@bash scripts/init-secrets.sh

deploy: init-secrets ## Base deploy (internal task runners)
	@chmod +x postgres/init-data.sh scripts/*.sh
	@test -f .env || { echo "ERROR: cp .env.example .env and edit N8N_HOST/ACME_EMAIL first."; exit 1; }
	$(COMPOSE) up -d

deploy-runners: init-secrets ## Prod deploy with external task-runner sidecars
	@chmod +x postgres/init-data.sh scripts/*.sh
	@test -f .env || { echo "ERROR: cp .env.example .env and also set N8N_RUNNERS_AUTH_TOKEN."; exit 1; }
	$(COMPOSE) -f docker-compose.yml -f docker-compose.runners.yml up -d

up: ## Start the stack (up -d)
	$(COMPOSE) up -d

down: ## Stop + remove containers (named data volumes preserved)
	$(COMPOSE) down

restart: ## Restart the stack
	$(COMPOSE) restart

ps: ## Container status
	$(COMPOSE) ps

logs: ## Follow logs (scope: make logs S=n8n)
	$(COMPOSE) logs -f $(S)

backup: ## Backup PostgreSQL + n8n data
	@bash scripts/backup.sh

restore: ## Restore a backup: make restore SRC=backups/<timestamp>
	@bash scripts/restore.sh $(SRC)

pin-digests: ## Print image sha256 digests to pin
	@bash scripts/pin-digests.sh
