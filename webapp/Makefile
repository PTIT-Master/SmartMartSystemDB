# Makefile for Supermarket Management System

# Variables
MAIN_PACKAGE = .
MIGRATE_PACKAGE = ./cmd/migrate
BINARY_NAME = supermarket-app

# Go commands
GOCMD = go
GOBUILD = $(GOCMD) build
GOCLEAN = $(GOCMD) clean
GOTEST = $(GOCMD) test
GOGET = $(GOCMD) get
GOMOD = $(GOCMD) mod
GORUN = $(GOCMD) run

# Targets
.PHONY: help build clean test run migrate migrate-drop migrate-schema deps

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build the application
	$(GOBUILD) -o $(BINARY_NAME) -v $(MAIN_PACKAGE)

clean: ## Clean build artifacts
	$(GOCLEAN)
	rm -f $(BINARY_NAME)

test: ## Run tests
	$(GOTEST) -v ./...

test-connection: ## Test database connection
	$(GORUN) test_connection.go

deps: ## Download dependencies
	$(GOMOD) download
	$(GOMOD) tidy

run: ## Run the application
	$(GORUN) $(MAIN_PACKAGE)

run-migrate: ## Run the application with migration
	$(GORUN) $(MAIN_PACKAGE) -migrate

migrate: ## Run database migration
	$(GORUN) $(MIGRATE_PACKAGE)

migrate-drop: ## Drop all tables and recreate (WARNING: Data loss!)
	$(GORUN) $(MIGRATE_PACKAGE) -drop

migrate-schema: ## Create schema only
	$(GORUN) $(MIGRATE_PACKAGE) -schema

dev: ## Run in development mode with auto-reload (requires air)
	@which air > /dev/null || (echo "Installing air..." && go install github.com/cosmtrek/air@latest)
	air

docker-db: ## Start PostgreSQL in Docker
	docker run --name supermarket-db \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_PASSWORD=postgres \
		-e POSTGRES_DB=supermarket \
		-p 5432:5432 \
		-d postgres:15-alpine

docker-db-stop: ## Stop PostgreSQL Docker container
	docker stop supermarket-db
	docker rm supermarket-db

# Default target
.DEFAULT_GOAL := help
