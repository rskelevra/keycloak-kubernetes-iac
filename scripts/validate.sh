#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="keycloak"
KEYCLOAK_URL="https://keycloak.local:8443"

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Test Kubernetes connectivity
test_kubernetes() {
    log_info "Testing Kubernetes connectivity..."
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Unable to connect to Kubernetes cluster"
        return 1
    fi
    
    log_success "Kubernetes cluster is accessible"
    
    # Check if namespace exists
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log_error "Namespace ${NAMESPACE} does not exist"
        return 1
    fi
    
    log_success "Namespace ${NAMESPACE} exists"
    return 0
}

# Test Pulumi stack
test_pulumi() {
    log_info "Testing Pulumi stack..."
    
    if ! command_exists pulumi; then
        log_warning "Pulumi not found, skipping Pulumi tests"
        return 0
    fi
    
    if ! pulumi stack ls | grep -q "dev"; then
        log_error "Pulumi stack 'dev' not found"
        return 1
    fi
    
    log_success "Pulumi stack 'dev' exists"
    
    # Test stack outputs
    local outputs=$(pulumi stack output --json 2>/dev/null || echo "{}")
    if [ "$outputs" != "{}" ]; then
        log_success "Pulumi stack outputs available"
        echo "   Available outputs: $(echo $outputs | jq -r 'keys[]' | tr '\n' ' ')"
    else
        log_warning "No Pulumi stack outputs found"
    fi
    
    return 0
}

# Test deployments
test_deployments() {
    log_info "Testing deployments..."
    
    local deployments=("postgres" "keycloak")
    local all_ready=true
    
    for deployment in "${deployments[@]}"; do
        log_info "Checking deployment: $deployment"
        
        if ! kubectl get deployment $deployment -n ${NAMESPACE} >/dev/null 2>&1; then
            log_error "Deployment $deployment not found"
            all_ready=false
            continue
        fi
        
        local ready_replicas=$(kubectl get deployment $deployment -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get deployment $deployment -n ${NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready_replicas" = "$desired_replicas" ]; then
            log_success "Deployment $deployment is ready ($ready_replicas/$desired_replicas)"
        else
            log_error "Deployment $deployment is not ready ($ready_replicas/$desired_replicas)"
            all_ready=false
        fi
    done
    
    if $all_ready; then
        log_success "All deployments are ready"
        return 0
    else
        log_error "Some deployments are not ready"
        return 1
    fi
}

# Test services
test_services() {
    log_info "Testing services..."
    
    local services=("postgres" "keycloak")
    local all_exist=true
    
    for service in "${services[@]}"; do
        if kubectl get service $service -n ${NAMESPACE} >/dev/null 2>&1; then
            log_success "Service $service exists"
        else
            log_error "Service $service not found"
            all_exist=false
        fi
    done
    
    if $all_exist; then
        log_success "All services exist"
        return 0
    else
        log_error "Some services are missing"
        return 1
    fi
}

# Test secrets
test_secrets() {
    log_info "Testing secrets..."
    
    local secrets=("keycloak-tls" "keycloak-db-credentials" "keycloak-admin-credentials")
    local all_exist=true
    
    for secret in "${secrets[@]}"; do
        if kubectl get secret $secret -n ${NAMESPACE} >/dev/null 2>&1; then
            log_success "Secret $secret exists"
        else
            log_error "Secret $secret not found"
            all_exist=false
        fi
    done
    
    if $all_exist; then
        log_success "All secrets exist"
        return 0
    else
        log_error "Some secrets are missing"
        return 1
    fi
}

# Test network connectivity
test_network() {
    log_info "Testing network connectivity..."
    
    # Check if port forwarding is active
    if pgrep -f "kubectl.*port-forward.*keycloak" >/dev/null; then
        log_success "Port forwarding is active"
    else
        log_warning "Port forwarding is not active, starting it..."
        nohup kubectl port-forward -n ${NAMESPACE} service/keycloak 8443:8443 > /tmp/keycloak-port-forward.log 2>&1 &
        sleep 5
    fi
    
    # Test local connectivity
    if nc -z localhost 8443 2>/dev/null; then
        log_success "Local port 8443 is accessible"
    else
        log_error "Local port 8443 is not accessible"
        return 1
    fi
    
    return 0
}

# Test Keycloak endpoint
test_keycloak_endpoint() {
    log_info "Testing Keycloak endpoint..."
    
    # Test HTTPS endpoint with curl (ignoring certificate)
    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "${KEYCLOAK_URL}/realms/master" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        log_success "Keycloak endpoint is responding (HTTP $http_code)"
    else
        log_error "Keycloak endpoint is not responding (HTTP $http_code)"
        return 1
    fi
    
    # Test admin console
    local admin_http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "${KEYCLOAK_URL}/admin/" 2>/dev/null || echo "000")
    
    if [ "$admin_http_code" = "200" ]; then
        log_success "Keycloak admin console is accessible (HTTP $admin_http_code)"
    else
        log_warning "Keycloak admin console returned HTTP $admin_http_code"
    fi
    
    return 0
}

# Test TLS certificate
test_tls() {
    log_info "Testing TLS certificate..."
    
    # Check certificate with openssl
    if command_exists openssl; then
        local cert_info=$(echo | openssl s_client -connect localhost:8443 -servername keycloak.local 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || echo "")
        
        if [ -n "$cert_info" ]; then
            log_success "TLS certificate is present"
            echo "   Certificate subject: $cert_info"
        else
            log_warning "Unable to retrieve TLS certificate information"
        fi
    else
        log_warning "OpenSSL not available, skipping certificate check"
    fi
    
    return 0
}

# Test database connectivity
test_database() {
    log_info "Testing database connectivity..."
    
    # Check if PostgreSQL pod is ready
    if kubectl get pods -n ${NAMESPACE} -l app=postgres | grep -q Running; then
        log_success "PostgreSQL pod is running"
    else
        log_error "PostgreSQL pod is not running"
        return 1
    fi
    
    # Test connection from Keycloak to PostgreSQL
    local keycloak_pod=$(kubectl get pods -n ${NAMESPACE} -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$keycloak_pod" ]; then
        local db_test=$(kubectl exec -n ${NAMESPACE} $keycloak_pod -- pg_isready -h postgres -p 5432 2>/dev/null || echo "failed")
        
        if [[ $db_test == *"accepting connections"* ]]; then
            log_success "Database connectivity from Keycloak confirmed"
        else
            log_warning "Unable to confirm database connectivity from Keycloak"
        fi
    else
        log_warning "No Keycloak pod found for database connectivity test"
    fi
    
    return 0
}

# Display summary
display_summary() {
    echo ""
    echo "=================================================="
    echo "           VALIDATION SUMMARY"
    echo "=================================================="
    echo ""
    
    if [ $1 -eq 0 ]; then
        log_success "All validation tests passed!"
        echo ""
        echo "🎉 Keycloak deployment is healthy and ready to use"
        echo ""
        echo "Access Information:"
        echo "  URL: ${KEYCLOAK_URL}"
        echo "  Admin Console: ${KEYCLOAK_URL}/admin/"
        echo ""
        
        # Get admin credentials if available
        if command_exists pulumi; then
            local admin_username=$(pulumi stack output keycloak-admin-username 2>/dev/null || echo "admin")
            local admin_password=$(pulumi stack output keycloak-admin-password 2>/dev/null || echo "Check Pulumi outputs")
            
            echo "Admin Credentials:"
            echo "  Username: $admin_username"
            echo "  Password: $admin_password"
            echo ""
        fi
        
        echo "Note: Accept the browser security warning for self-signed certificate"
    else
        log_error "Some validation tests failed!"
        echo ""
        echo "🔧 Troubleshooting:"
        echo "  - Check pod status: kubectl get pods -n ${NAMESPACE}"
        echo "  - Check logs: kubectl logs -f deployment/keycloak -n ${NAMESPACE}"
        echo "  - Check events: kubectl get events -n ${NAMESPACE}"
        echo ""
    fi
    
    echo ""
}

# Main validation function
main() {
    echo ""
    echo "=================================================="
    echo "         KEYCLOAK DEPLOYMENT VALIDATION"
    echo "=================================================="
    echo ""
    
    local tests_passed=0
    local tests_failed=0
    
    # Run tests
    test_kubernetes && ((tests_passed++)) || ((tests_failed++))
    test_pulumi && ((tests_passed++)) || ((tests_failed++))
    test_deployments && ((tests_passed++)) || ((tests_failed++))
    test_services && ((tests_passed++)) || ((tests_failed++))
    test_secrets && ((tests_passed++)) || ((tests_failed++))
    test_network && ((tests_passed++)) || ((tests_failed++))
    test_keycloak_endpoint && ((tests_passed++)) || ((tests_failed++))
    test_tls && ((tests_passed++)) || ((tests_failed++))
    test_database && ((tests_passed++)) || ((tests_failed++))
    
    # Display results
    echo ""
    log_info "Tests completed: $((tests_passed + tests_failed))"
    log_success "Tests passed: $tests_passed"
    
    if [ $tests_failed -gt 0 ]; then
        log_error "Tests failed: $tests_failed"
        display_summary 1
        exit 1
    else
        display_summary 0
        exit 0
    fi
}

# Run main function
main "$@"
