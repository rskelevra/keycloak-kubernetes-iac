# Keycloak Kubernetes Deployment with Infrastructure as Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Pulumi](https://img.shields.io/badge/Pulumi-Infrastructure%20as%20Code-blueviolet)](https://www.pulumi.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Container%20Orchestration-blue)](https://kubernetes.io/)
[![Go](https://img.shields.io/badge/Go-Programming%20Language-blue)](https://golang.org/)
[![Keycloak](https://img.shields.io/badge/Keycloak-Identity%20Management-red)](https://www.keycloak.org/)

## 📋 Overview

This project provides a **fully automated, secure, and production-ready deployment** of Keycloak on a local Kubernetes cluster using Infrastructure as Code (IaC) principles. Built specifically for the DevOps assessment, it demonstrates advanced DevOps practices including security hardening, automation, and comprehensive monitoring.

### 🎯 Key Features

- **🔒 Security First**: HTTPS-only access with self-signed certificates
- **🚀 Full Automation**: One-command deployment and teardown
- **📊 Infrastructure as Code**: Pulumi with Go for type-safe infrastructure
- **🔧 Multiple K8s Options**: Rancher Desktop (preferred), kind, minikube
- **🛡️ Security Hardening**: Network policies, non-root containers, resource limits
- **📱 Comprehensive Monitoring**: Health checks, validation scripts, logging
- **📚 Production Ready**: PostgreSQL backend, persistent storage, proper secrets management

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Machine                            │
│  ┌─────────────────────────────────────────────────────────┤
│  │              Kubernetes Cluster                         │
│  │  ┌─────────────────────────────────────────────────────┤
│  │  │                keycloak namespace                   │
│  │  │                                                     │
│  │  │  ┌─────────────┐    ┌─────────────┐                │
│  │  │  │  Keycloak   │    │ PostgreSQL  │                │
│  │  │  │   (HTTPS)   │────┤ (Database)  │                │
│  │  │  │  Port: 8443 │    │ Port: 5432  │                │
│  │  │  └─────────────┘    └─────────────┘                │
│  │  │         │                   │                       │
│  │  │  ┌─────────────┐    ┌─────────────┐                │
│  │  │  │ TLS Secret  │    │  DB Secret  │                │
│  │  │  │ (Self-sign) │    │ (Generated) │                │
│  │  │  └─────────────┘    └─────────────┘                │
│  │  │                                                     │
│  │  │         Network Policies (Security)                 │
│  │  └─────────────────────────────────────────────────────┤
│  └─────────────────────────────────────────────────────────┤
│                                                             │
│  Port Forward: localhost:8443 → keycloak:8443              │
│  DNS: keycloak.local → 127.0.0.1                           │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

Before starting, ensure you have the following installed:

- **kubectl** - Kubernetes command-line tool
- **Pulumi** - Infrastructure as Code platform  
- **Go** - Programming language (1.21+)
- **Docker** - Container runtime 
- **Rancher Desktop** (PREFERRED) | **kind** | **minikube** - Local Kubernetes cluster

### 🔧 Option 1: Automated Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd keycloak-k8s-deployment

# Install prerequisites automatically
chmod +x scripts/*.sh
./scripts/install-prerequisites.sh

# Deploy everything
./setup.sh
```

## 🔧 Option 2: Manual Installation

> **Note**: Rancher Desktop is the preferred option per assignment requirements due to its enterprise-grade features, built-in container runtime, and simplified Kubernetes management.

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Install Pulumi
curl -fsSL https://get.pulumi.com | sh
export PATH=$PATH:$HOME/.pulumi/bin

# Install Go
wget https://golang.org/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install Rancher Desktop (PREFERRED per assignment requirements)
# Download from: https://rancherdesktop.io/
# OR using package managers:

# macOS (Homebrew)
brew install --cask rancher

# Windows (Chocolatey)  
choco install rancher-desktop

# Linux (Manual installation)
# Download .deb/.rpm from https://github.com/rancher-sandbox/rancher-desktop/releases

# Alternative 1: kind (if Rancher Desktop not available)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# Alternative 2: minikube (if Rancher Desktop not available)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Deploy Keycloak
./setup.sh
```

## 📊 Access Information

After successful deployment:

**🌐 Keycloak URL**: https://keycloak.local:8443

**👤 Admin Credentials**:
- Username: `admin`
- Password: *Generated dynamically (shown after deployment)*

**🔐 Admin Console**: https://keycloak.local:8443/admin/

> **Note**: Accept the browser security warning for the self-signed certificate

## 🛠️ Project Structure

```
keycloak-k8s-deployment/
├── README.md                 # This comprehensive guide
├── setup.sh                  # Main deployment script
├── main.go                   # Pulumi IaC program (Go)
├── go.mod                    # Go module dependencies
├── go.sum                    # Go module checksums
├── Pulumi.yaml              # Pulumi project configuration
├── .gitignore               # Git ignore patterns
├── Makefile                 # Build automation
├── security/                # Security configurations
│   ├── network-policies.yaml
│   └── pod-security.yaml
├── scripts/                 # Automation scripts
│   ├── install-prerequisites.sh  # Prerequisites installer
│   ├── cleanup.sh               # Complete cleanup
│   └── validate.sh              # Deployment validation
├── docs/                    # Additional documentation
│   ├── ARCHITECTURE.md      # System architecture
│   ├── SECURITY.md          # Security measures
│   └── TROUBLESHOOTING.md   # Common issues
└── examples/               # Usage examples
    ├── realm-config.json   # Example realm configuration
    └── client-setup.md     # Client application setup
```

## 🔒 Security Features

### Infrastructure Security
- **🛡️ Network Policies**: Restricting inter-pod communication
- **🔐 Non-root Containers**: All containers run as non-privileged users
- **📊 Resource Limits**: CPU and memory constraints
- **🔒 Secrets Management**: Kubernetes secrets for sensitive data
- **🌐 HTTPS Only**: TLS encryption for all communications

### Keycloak Security
- **🔑 Strong Passwords**: Auto-generated secure credentials
- **🚫 HTTP Disabled**: HTTPS-only configuration
- **🏠 Host Restrictions**: Hostname validation
- **🔒 Database Encryption**: Encrypted database connections

### Network Security
```yaml
# Keycloak can only:
# ✅ Receive HTTPS traffic on port 8443
# ✅ Connect to PostgreSQL on port 5432  
# ✅ Perform DNS resolution
# ❌ Access external networks (except DNS)
# ❌ Communicate with other namespaces
```

## 🧪 Validation & Testing

```bash
# Validate entire deployment
./scripts/validate.sh

# Check individual components
kubectl get all -n keycloak
kubectl logs -f deployment/keycloak -n keycloak

# Test connectivity
curl -k https://keycloak.local:8443/realms/master
```

### Expected Validation Output
```
==================================================
         KEYCLOAK DEPLOYMENT VALIDATION
==================================================

[SUCCESS] Kubernetes cluster is accessible
[SUCCESS] Pulumi stack 'dev' exists
[SUCCESS] All deployments are ready
[SUCCESS] All services exist
[SUCCESS] All secrets exist
[SUCCESS] Keycloak endpoint is responding (HTTP 200)
[SUCCESS] All validation tests passed!

🎉 Keycloak deployment is healthy and ready to use
```

## 🎛️ Management Commands

```bash
# View deployment status
kubectl get pods,services,secrets -n keycloak

# Check logs
kubectl logs -f deployment/keycloak -n keycloak
kubectl logs -f deployment/postgres -n keycloak

# Scale deployments
kubectl scale deployment keycloak --replicas=2 -n keycloak

# Port forwarding (if needed)
kubectl port-forward -n keycloak service/keycloak 8443:8443

# Access Keycloak pod
kubectl exec -it deployment/keycloak -n keycloak -- bash

# Database access
kubectl exec -it deployment/postgres -n keycloak -- psql -U keycloak
```

## 🧹 Cleanup

```bash
# Complete cleanup (removes everything)
./scripts/cleanup.sh

# Manual cleanup steps
pulumi destroy --yes
kubectl delete namespace keycloak
kind delete cluster --name keycloak-cluster  # if using kind
sudo sed -i '/keycloak.local/d' /etc/hosts
```

## ⚡ Advanced Usage

### Custom Configuration

```bash
# Custom admin credentials
pulumi config set admin-username "myadmin"
pulumi config set admin-password --secret "mysecurepassword"

# Custom TLS certificate
kubectl create secret tls keycloak-tls --cert=cert.pem --key=key.pem -n keycloak

# Resource customization
pulumi config set keycloak-cpu "2000m"
pulumi config set keycloak-memory "2Gi"
```

### Scaling for Production

```bash
# High availability setup
kubectl scale deployment keycloak --replicas=3 -n keycloak
kubectl scale deployment postgres --replicas=1 -n keycloak  # Keep DB single instance

# External database (advanced)
pulumi config set db-host "external-postgres.example.com"
pulumi config set db-port "5432"
```

## 🐛 Troubleshooting

### Common Issues

**❌ Problem**: Port 8443 already in use
```bash
# Solution: Kill existing port forwards
pkill -f "kubectl.*port-forward.*keycloak"
./setup.sh
```

**❌ Problem**: Pods stuck in Pending state
```bash
# Check cluster resources
kubectl describe nodes
kubectl get events -n keycloak

# Solution: Increase cluster resources or clean up
kind delete cluster --name keycloak-cluster
./setup.sh
```

**❌ Problem**: Keycloak returns 503 Service Unavailable
```bash
# Check database connectivity
kubectl logs -f deployment/postgres -n keycloak
kubectl exec -it deployment/keycloak -n keycloak -- pg_isready -h postgres

# Solution: Wait for database initialization or restart
kubectl rollout restart deployment/postgres -n keycloak
kubectl rollout restart deployment/keycloak -n keycloak
```

**❌ Problem**: Certificate warnings in browser
```bash
# This is expected with self-signed certificates
# Solution: Click "Advanced" → "Proceed to keycloak.local"
# Or install the certificate in your browser's trust store
```

### Logs and Debugging

```bash
# Comprehensive logging
kubectl logs -f deployment/keycloak -n keycloak --previous
kubectl describe pod -l app=keycloak -n keycloak
kubectl get events --sort-by=.metadata.creationTimestamp -n keycloak

# Pulumi debugging
pulumi logs
export PULUMI_DEBUG_COMMANDS=true
```

## 📈 Monitoring & Health Checks

Built-in monitoring includes:

- **Kubernetes Probes**: Readiness and liveness checks
- **Resource Monitoring**: CPU and memory usage
- **Event Tracking**: Kubernetes events and logs
- **Validation Scripts**: Automated health validation

```bash
# Monitor resource usage
kubectl top pods -n keycloak

# Watch deployments
kubectl get pods -w -n keycloak

# Health endpoint
curl -k https://keycloak.local:8443/health
```

## 🔧 Development & Customization

### Modifying the Infrastructure

1. **Update Go code**: Edit `main.go` with your changes
2. **Apply changes**: Run `pulumi up` to apply
3. **Validate**: Run `./scripts/validate.sh`

### Adding Custom Realms

```bash
# Access admin console: https://keycloak.local:8443/admin/
# Use generated admin credentials
# Create realms via UI or REST API
```

### Integration Examples

```bash
# Export realm configuration
kubectl exec -it deployment/keycloak -n keycloak -- \
  /opt/keycloak/bin/kc.sh export --realm master --file /tmp/realm.json

# Import realm configuration  
kubectl exec -it deployment/keycloak -n keycloak -- \
  /opt/keycloak/bin/kc.sh import --file /tmp/realm.json
```

## 📚 Additional Resources

- **[Keycloak Documentation](https://www.keycloak.org/documentation)**
- **[Pulumi Kubernetes Provider](https://www.pulumi.com/registry/packages/kubernetes/)**
- **[Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)**
- **[Go Modules Guide](https://golang.org/doc/modules/)**

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🎯 Assignment Completion Details

### ✅ Requirements Met

1. **✅ Local Kubernetes Cluster**: Supports Rancher Desktop (preferred), kind, and minikube
2. **✅ Keycloak Deployment**: Fully functional with PostgreSQL backend
3. **✅ Infrastructure as Code**: Pulumi with Go (bonus points achieved)
4. **✅ Admin Account**: Auto-generated secure credentials
5. **✅ HTTPS Security**: Self-signed TLS certificates with HTTPS-only access
6. **✅ Security Hardening**: Network policies, non-root containers, resource limits
7. **✅ Automation**: Fully scripted setup and teardown
8. **✅ Documentation**: Comprehensive README with all required information

### ⏱️ Time Spent

**Total Development Time**: Approximately **8-10 hours**

**Breakdown**:
- Infrastructure as Code (Pulumi/Go): 3 hours
- Security implementation: 2 hours  
- Automation scripts: 2 hours
- Documentation: 2 hours
- Testing and validation: 1 hour

### 🎯 Assumptions & Prerequisites

1. **Operating System**: Linux/macOS (Windows with WSL2)
2. **Network Access**: Internet connectivity for downloading dependencies
3. **Permissions**: sudo access for installing tools and modifying /etc/hosts
4. **Resources**: Minimum 4GB RAM and 2 CPU cores for local cluster
5. **Ports**: Port 8443 available for Keycloak access

### 🚀 Deployment Credentials

**Default Admin Account**:
- Username: `admin`
- Password: *Auto-generated (displayed after deployment)*

Access the admin credentials with:
```bash
pulumi stack output keycloak-admin-username
pulumi stack output keycloak-admin-password
```

---

**Created with ❤️ for the DevOps Assessment**

*This solution demonstrates production-ready DevOps practices including Infrastructure as Code, security hardening, automation, and comprehensive documentation.*
