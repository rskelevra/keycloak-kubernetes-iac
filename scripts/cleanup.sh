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
    # Check which cluster type and cleanup accordingly (k3d first since it's our primary)
    if command -v k3d >/dev/null 2>&1 && k3d cluster list | grep -q "${CLUSTER_NAME}"; then
        log_info "Deleting k3d cluster: ${CLUSTER_NAME}"
        k3d cluster delete ${CLUSTER_NAME}
        log_success "k3d cluster deleted"
        
        # Clean up any leftover kubeconfig entries
        log_info "Cleaning up k3d kubeconfig entries..."
        kubectl config delete-context k3d-${CLUSTER_NAME} 2>/dev/null || true
        kubectl config delete-cluster k3d-${CLUSTER_NAME} 2>/dev/null || true
        
    elif command -v kind >/dev/null 2>&1 && kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
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

# Cleanup Docker resources (k3d uses Docker containers)
cleanup_docker_resources() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Cleaning up Docker resources..."
        
        # Remove any leftover k3d containers
        local containers=$(docker ps -aq --filter "label=k3d.cluster=${CLUSTER_NAME}" 2>/dev/null || true)
        if [ -n "$containers" ]; then
            log_info "Removing k3d containers..."
            docker rm -f $containers 2>/dev/null || true
        fi
        
        # Remove any leftover k3d networks
        local networks=$(docker network ls --filter "label=k3d.cluster=${CLUSTER_NAME}" -q 2>/dev/null || true)
        if [ -n "$networks" ]; then
            log_info "Removing k3d networks..."
            docker network rm $networks 2>/dev/null || true
        fi
        
        # Remove any leftover k3d volumes
        local volumes=$(docker volume ls --filter "label=k3d.cluster=${CLUSTER_NAME}" -q 2>/dev/null || true)
        if [ -n "$volumes" ]; then
            log_info "Removing k3d volumes..."
            docker volume rm $volumes 2>/dev/null || true
        fi
        
        log_success "Docker cleanup completed"
    fi
}

# Confirmation prompt
confirm_cleanup() {
    echo ""
    echo "⚠️  WARNING: This will:"
    echo "   - Destroy all Keycloak infrastructure"
    echo "   - Delete the Kubernetes cluster (k3d/kind/minikube)"
    echo "   - Remove port forwarding"
    echo "   - Clean up DNS entries"
    echo "   - Remove Docker containers/networks/volumes (for k3d)"
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
    cleanup_docker_resources
}

# Run main function
main "$@"