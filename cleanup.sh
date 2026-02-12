#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="keycloak-cluster"
NAMESPACE="keycloak"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup_deployment() {
    echo ""
    echo "=================================================="
    echo "         KEYCLOAK CLEANUP SCRIPT"
    echo "=================================================="
    echo ""
    
    log_info "Starting cleanup process..."
    
    # Stop port forwarding
    log_info "Stopping port forwarding..."
    pkill -f "kubectl.*port-forward.*keycloak" || true
    
    # Destroy Pulumi stack
    if command -v pulumi >/dev/null 2>&1; then
        log_info "Destroying Pulumi infrastructure..."
        if pulumi stack ls 2>/dev/null | grep -q "dev"; then
            pulumi stack select dev
            pulumi destroy --yes
            log_success "Pulumi infrastructure destroyed"
        else
            log_warning "No Pulumi stack found to destroy"
        fi
    else
        log_warning "Pulumi not found, skipping infrastructure cleanup"
    fi
    
    # Cleanup Kubernetes resources manually if needed
    if kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log_info "Cleaning up Kubernetes namespace..."
        kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
        log_success "Namespace ${NAMESPACE} deleted"
    fi
    
    # Cleanup cluster based on type
    cleanup_cluster
    
    # Remove /etc/hosts entry
    cleanup_hosts_file
    
    # Cleanup temporary files
    log_info "Cleaning up temporary files..."
    rm -f /tmp/kind-config.yaml
    rm -f /tmp/keycloak-port-forward.log
    
    log_success "Cleanup completed successfully!"
    echo ""
}

# Cleanup cluster
cleanup_cluster() {
    # Check which cluster type and cleanup accordingly
    if command -v kind >/dev/null 2>&1 && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Deleting kind cluster: ${CLUSTER_NAME}"
        kind delete cluster --name ${CLUSTER_NAME}
        log_success "Kind cluster deleted"
    elif command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
        read -p "Do you want to delete the minikube cluster? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting minikube cluster..."
            minikube delete
            log_success "Minikube cluster deleted"
        else
            log_info "Minikube cluster preserved"
        fi
    elif command -v rancher-desktop >/dev/null 2>&1; then
        log_info "Rancher Desktop detected - cluster cleanup skipped"
        log_warning "Please manually reset Rancher Desktop if needed"
    else
        log_info "No cluster cleanup needed"
    fi
}

# Cleanup hosts file
cleanup_hosts_file() {
    if grep -q "keycloak.local" /etc/hosts; then
        log_info "Removing keycloak.local from /etc/hosts (requires sudo)"
        sudo sed -i '/keycloak.local/d' /etc/hosts
        log_success "Removed keycloak.local from /etc/hosts"
    else
        log_info "No keycloak.local entry found in /etc/hosts"
    fi
}

# Confirmation prompt
confirm_cleanup() {
    echo ""
    echo "⚠️  WARNING: This will:"
    echo "   - Destroy all Keycloak infrastructure"
    echo "   - Delete the Kubernetes cluster (for kind/minikube)"
    echo "   - Remove port forwarding"
    echo "   - Clean up DNS entries"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Main execution
main() {
    confirm_cleanup
    cleanup_deployment
}

# Run main function
main "$@"
