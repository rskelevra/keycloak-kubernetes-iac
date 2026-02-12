# Keycloak Kubernetes Deployment Makefile
.PHONY: help install deploy validate cleanup dev test lint format deps

# Default target
.DEFAULT_GOAL := help

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Configuration
NAMESPACE := keycloak
STACK := dev
CLUSTER_NAME := keycloak-cluster

## Display help information
help:
	@echo ""
	@echo "$(GREEN)Keycloak Kubernetes Deployment$(NC)"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /' | column -t -s ':'
	@echo ""

## Install prerequisites and tools
install:
	@echo "$(GREEN)Installing prerequisites...$(NC)"
	@chmod +x scripts/*.sh setup.sh
	@./scripts/install-prerequisites.sh

## Deploy complete Keycloak infrastructure
deploy:
	@echo "$(GREEN)Deploying Keycloak infrastructure...$(NC)"
	@./setup.sh

## Validate deployment health and status
validate:
	@echo "$(GREEN)Validating deployment...$(NC)"
	@./scripts/validate.sh

## Complete cleanup of all resources
cleanup:
	@echo "$(RED)Cleaning up deployment...$(NC)"
	@./scripts/cleanup.sh

## Quick development setup (install + deploy + validate)
dev: install deploy validate
	@echo "$(GREEN)Development environment ready!$(NC)"

## Run tests and validation
test: validate
	@echo "$(GREEN)Running additional tests...$(NC)"
	@kubectl get all -n $(NAMESPACE)
	@kubectl get secrets -n $(NAMESPACE)

## Lint Go code
lint:
	@echo "$(GREEN)Linting Go code...$(NC)"
	@go fmt ./...
	@go vet ./...
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "$(YELLOW)golangci-lint not installed, skipping advanced linting$(NC)"; \
	fi

## Format Go code
format:
	@echo "$(GREEN)Formatting Go code...$(NC)"
	@go fmt ./...

## Download and verify Go dependencies
deps:
	@echo "$(GREEN)Managing Go dependencies...$(NC)"
	@go mod download
	@go mod verify
	@go mod tidy

## Show deployment status
status:
	@echo "$(GREEN)Deployment Status:$(NC)"
	@echo ""
	@if kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
		echo "  Namespace: $(GREEN)✓ $(NAMESPACE)$(NC)"; \
		kubectl get pods,svc,secrets -n $(NAMESPACE); \
	else \
		echo "  Namespace: $(RED)✗ $(NAMESPACE) not found$(NC)"; \
	fi
	@echo ""
	@if pulumi stack ls 2>/dev/null | grep -q "$(STACK)"; then \
		echo "  Pulumi Stack: $(GREEN)✓ $(STACK)$(NC)"; \
		pulumi stack output --json 2>/dev/null | jq -r 'to_entries[] | "    \(.key): \(.value)"' || true; \
	else \
		echo "  Pulumi Stack: $(RED)✗ $(STACK) not found$(NC)"; \
	fi

## Show logs from Keycloak deployment
logs:
	@echo "$(GREEN)Keycloak Logs:$(NC)"
	@kubectl logs -f deployment/keycloak -n $(NAMESPACE)

## Show logs from PostgreSQL deployment
logs-db:
	@echo "$(GREEN)PostgreSQL Logs:$(NC)"
	@kubectl logs -f deployment/postgres -n $(NAMESPACE)

## Port forward Keycloak service (background)
port-forward:
	@echo "$(GREEN)Setting up port forwarding...$(NC)"
	@pkill -f "kubectl.*port-forward.*keycloak" || true
	@nohup kubectl port-forward -n $(NAMESPACE) service/keycloak 8443:8443 > /tmp/keycloak-port-forward.log 2>&1 &
	@sleep 2
	@echo "  Port forwarding active: https://keycloak.local:8443"
	@echo "  Logs: /tmp/keycloak-port-forward.log"

## Stop port forwarding
stop-port-forward:
	@echo "$(GREEN)Stopping port forwarding...$(NC)"
	@pkill -f "kubectl.*port-forward.*keycloak" || echo "No port forwarding process found"

## Access Keycloak admin console
console: port-forward
	@echo "$(GREEN)Opening Keycloak admin console...$(NC)"
	@echo "  URL: https://keycloak.local:8443/admin/"
	@if command -v pulumi >/dev/null 2>&1; then \
		echo "  Username: $$(pulumi stack output keycloak-admin-username 2>/dev/null || echo 'admin')"; \
		echo "  Password: $$(pulumi stack output keycloak-admin-password 2>/dev/null || echo 'Check pulumi outputs')"; \
	fi
	@if command -v xdg-open >/dev/null 2>&1; then \
		xdg-open https://keycloak.local:8443/admin/ 2>/dev/null & \
	elif command -v open >/dev/null 2>&1; then \
		open https://keycloak.local:8443/admin/ 2>/dev/null & \
	fi

## Update Go dependencies
update-deps:
	@echo "$(GREEN)Updating Go dependencies...$(NC)"
	@go get -u ./...
	@go mod tidy

## Clean build artifacts and caches
clean:
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	@go clean
	@go clean -cache
	@go clean -modcache
	@rm -f *.log
	@rm -f /tmp/keycloak-port-forward.log
	@rm -f /tmp/kind-config.yaml

## Security scan (if tools available)
security-scan:
	@echo "$(GREEN)Running security scans...$(NC)"
	@if command -v gosec >/dev/null 2>&1; then \
		gosec ./...; \
	else \
		echo "$(YELLOW)gosec not installed, install with: go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest$(NC)"; \
	fi
	@if command -v trivy >/dev/null 2>&1; then \
		trivy fs .; \
	else \
		echo "$(YELLOW)trivy not installed, install from: https://aquasecurity.github.io/trivy/$(NC)"; \
	fi

## Generate project documentation
docs:
	@echo "$(GREEN)Generating documentation...$(NC)"
	@if command -v godoc >/dev/null 2>&1; then \
		echo "Starting godoc server on http://localhost:6060"; \
		godoc -http=:6060 & \
	else \
		echo "$(YELLOW)godoc not installed, install with: go install golang.org/x/tools/cmd/godoc@latest$(NC)"; \
	fi

## Build for different platforms
build:
	@echo "$(GREEN)Building binaries...$(NC)"
	@mkdir -p dist
	@GOOS=linux GOARCH=amd64 go build -o dist/keycloak-deploy-linux-amd64 .
	@GOOS=darwin GOARCH=amd64 go build -o dist/keycloak-deploy-darwin-amd64 .
	@GOOS=windows GOARCH=amd64 go build -o dist/keycloak-deploy-windows-amd64.exe .
	@echo "  Binaries created in dist/"

## Show resource usage
resources:
	@echo "$(GREEN)Resource Usage:$(NC)"
	@if kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
		kubectl top pods -n $(NAMESPACE) 2>/dev/null || echo "Metrics server not available"; \
		kubectl describe resourcequotas -n $(NAMESPACE) 2>/dev/null || true; \
	else \
		echo "  Namespace $(NAMESPACE) not found"; \
	fi

## Restart deployment
restart:
	@echo "$(GREEN)Restarting deployments...$(NC)"
	@kubectl rollout restart deployment/keycloak -n $(NAMESPACE)
	@kubectl rollout restart deployment/postgres -n $(NAMESPACE)
	@kubectl rollout status deployment/keycloak -n $(NAMESPACE)
	@kubectl rollout status deployment/postgres -n $(NAMESPACE)

## Scale deployments
scale:
	@echo "$(GREEN)Scaling Keycloak deployment...$(NC)"
	@read -p "Enter number of replicas (current: $$(kubectl get deployment keycloak -n $(NAMESPACE) -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 'N/A')): " replicas; \
	kubectl scale deployment keycloak --replicas=$$replicas -n $(NAMESPACE)

## Check prerequisites
check:
	@echo "$(GREEN)Checking prerequisites...$(NC)"
	@echo -n "  kubectl: "; command -v kubectl >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  pulumi: "; command -v pulumi >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  go: "; command -v go >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  docker: "; command -v docker >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  kind: "; command -v kind >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  minikube: "; command -v minikube >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"
	@echo -n "  rancher-desktop: "; command -v rancher-desktop >/dev/null && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)"

## Full reset (cleanup + fresh deploy)
reset: cleanup deploy validate
	@echo "$(GREEN)Full reset completed!$(NC)"

## Show version information
version:
	@echo "$(GREEN)Version Information:$(NC)"
	@echo "  Go: $$(go version 2>/dev/null || echo 'Not installed')"
	@echo "  kubectl: $$(kubectl version --client --short 2>/dev/null || echo 'Not installed')"
	@echo "  Pulumi: $$(pulumi version 2>/dev/null || echo 'Not installed')"
	@echo "  Docker: $$(docker --version 2>/dev/null || echo 'Not installed')"
	@echo "  kind: $$(kind --version 2>/dev/null || echo 'Not installed')"
	@if command -v minikube >/dev/null 2>&1; then \
		echo "  minikube: $$(minikube version --short 2>/dev/null || echo 'Not installed')"; \
	fi

## Show useful URLs and access information
info:
	@echo "$(GREEN)Access Information:$(NC)"
	@echo ""
	@echo "  🌐 Keycloak URL: https://keycloak.local:8443"
	@echo "  🔧 Admin Console: https://keycloak.local:8443/admin/"
	@echo "  📊 Master Realm: https://keycloak.local:8443/realms/master"
	@echo ""
	@if command -v pulumi >/dev/null 2>&1 && pulumi stack ls 2>/dev/null | grep -q "$(STACK)"; then \
		echo "  👤 Admin Credentials:"; \
		echo "     Username: $$(pulumi stack output keycloak-admin-username 2>/dev/null || echo 'admin')"; \
		echo "     Password: $$(pulumi stack output keycloak-admin-password 2>/dev/null || echo 'Check pulumi outputs')"; \
	fi
	@echo ""
	@echo "  📝 Useful Commands:"
	@echo "     make logs       - View Keycloak logs"
	@echo "     make status     - Show deployment status"
	@echo "     make validate   - Run health checks"
	@echo "     make cleanup    - Remove everything"
	@echo ""
