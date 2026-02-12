# Troubleshooting Guide

This guide covers common issues and their solutions when deploying Keycloak on Kubernetes.

## 🔍 Quick Diagnostics

### Health Check Commands

```bash
# Overall deployment status
make status

# Validate deployment
./scripts/validate.sh

# Check pod status
kubectl get pods -n keycloak

# View recent events
kubectl get events -n keycloak --sort-by=.metadata.creationTimestamp
```

## 🚨 Common Issues

### 1. Pods Stuck in Pending State

**Symptoms:**
```bash
$ kubectl get pods -n keycloak
NAME                        READY   STATUS    RESTARTS   AGE
keycloak-xxx-yyy           0/1     Pending   0          5m
postgres-aaa-bbb           0/1     Pending   0          5m
```

**Causes & Solutions:**

**Insufficient Resources:**
```bash
# Check node resources
kubectl describe nodes
kubectl top nodes

# Solution: Free up resources or add nodes
docker system prune -a  # For local Docker
```

**Missing Storage Class:**
```bash
# Check available storage classes
kubectl get storageclass

# Solution: Use emptyDir (already configured) or install local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

### 2. Keycloak Pod CrashLoopBackOff

**Symptoms:**
```bash
$ kubectl get pods -n keycloak
NAME                        READY   STATUS             RESTARTS   AGE
keycloak-xxx-yyy           0/1     CrashLoopBackOff   3          10m
```

**Diagnosis:**
```bash
# Check logs
kubectl logs keycloak-xxx-yyy -n keycloak
kubectl logs keycloak-xxx-yyy -n keycloak --previous

# Common error patterns:
# - Database connection failed
# - TLS certificate issues
# - Memory/resource limits
```

**Solutions:**

**Database Connection Issues:**
```bash
# Test database connectivity
kubectl exec -it deployment/postgres -n keycloak -- pg_isready -h localhost -p 5432

# Check database logs
kubectl logs deployment/postgres -n keycloak

# Reset database if needed
kubectl delete pod -l app=postgres -n keycloak
```

**TLS Certificate Issues:**
```bash
# Check TLS secret
kubectl get secret keycloak-tls -n keycloak -o yaml

# Recreate certificates
pulumi destroy --yes
pulumi up --yes
```

**Memory Issues:**
```bash
# Check resource usage
kubectl top pods -n keycloak

# Increase memory limits (edit main.go)
Resources: &corev1.ResourceRequirementsArgs{
    Limits: pulumi.StringMap{
        "memory": pulumi.String("2Gi"),  // Increased from 1Gi
        "cpu":    pulumi.String("1000m"),
    },
}
```

### 3. Database Connection Failures

**Symptoms:**
```
ERROR: Failed to connect to database
FATAL: password authentication failed for user "keycloak"
```

**Solutions:**

**Check Database Status:**
```bash
# Verify PostgreSQL is running
kubectl get pods -l app=postgres -n keycloak

# Test connection from Keycloak pod
kubectl exec -it deployment/keycloak -n keycloak -- \
  pg_isready -h postgres -p 5432 -U keycloak
```

**Check Secrets:**
```bash
# Verify database secrets exist
kubectl get secret keycloak-db-credentials -n keycloak

# Check secret contents (base64 encoded)
kubectl get secret keycloak-db-credentials -n keycloak -o jsonpath='{.data.username}' | base64 -d
kubectl get secret keycloak-db-credentials -n keycloak -o jsonpath='{.data.password}' | base64 -d
```

**Reset Database:**
```bash
# Delete and recreate database
kubectl delete deployment postgres -n keycloak
kubectl delete pvc -l app=postgres -n keycloak  # If using PVCs
pulumi up --yes
```

### 4. Port Forwarding Issues

**Symptoms:**
```
Unable to listen on port 8443: address already in use
```

**Solutions:**
```bash
# Find and kill existing port forwards
pkill -f "kubectl.*port-forward.*keycloak"
lsof -ti:8443 | xargs kill -9

# Restart port forwarding
make port-forward
```

### 5. DNS Resolution Issues

**Symptoms:**
```
curl: (6) Could not resolve host: keycloak.local
```

**Solutions:**

**Check /etc/hosts:**
```bash
# Verify entry exists
grep keycloak.local /etc/hosts

# Add if missing
echo "127.0.0.1 keycloak.local" | sudo tee -a /etc/hosts
```

**Alternative: Use IP directly:**
```bash
# Use localhost instead
curl -k https://localhost:8443/realms/master
```

### 6. TLS Certificate Warnings

**Symptoms:**
```
Your connection is not private
NET::ERR_CERT_AUTHORITY_INVALID
```

**This is Expected** with self-signed certificates.

**Solutions:**

**Browser: Click "Advanced" → "Proceed to keycloak.local"**

**cURL: Use -k flag:**
```bash
curl -k https://keycloak.local:8443/realms/master
```

**Application: Disable certificate verification (development only):**
```javascript
process.env["NODE_TLS_REJECT_UNAUTHORIZED"] = 0;
```

### 7. Pulumi State Issues

**Symptoms:**
```
error: could not create stack: stack already exists
error: stack not found
```

**Solutions:**
```bash
# List existing stacks
pulumi stack ls

# Select correct stack
pulumi stack select dev

# Remove corrupted stack
pulumi stack rm dev --yes
pulumi stack init dev

# Reset state
rm -rf ~/.pulumi
pulumi login --local
```

### 8. Kubernetes Context Issues

**Symptoms:**
```
The connection to the server localhost:8080 was refused
error: You must be logged in to the server
```

**Solutions:**
```bash
# Check current context
kubectl config current-context

# List available contexts
kubectl config get-contexts

# Switch context
kubectl config use-context kind-keycloak-cluster  # For kind
kubectl config use-context rancher-desktop        # For Rancher Desktop

# Test connectivity
kubectl cluster-info
```

### 9. Resource Quota Exceeded

**Symptoms:**
```
pods "keycloak-xxx-yyy" is forbidden: exceeded quota
```

**Solutions:**
```bash
# Check resource usage
kubectl describe resourcequota -n keycloak

# Clean up unused resources
kubectl delete pod --field-selector=status.phase==Succeeded -n keycloak
kubectl delete pod --field-selector=status.phase==Failed -n keycloak

# Increase quotas (edit security/pod-security.yaml)
```

### 10. Network Policy Blocking Traffic

**Symptoms:**
```
Connection timeout
Service unreachable
```

**Solutions:**
```bash
# Temporarily remove network policies
kubectl delete networkpolicy --all -n keycloak

# Test connectivity
curl -k https://localhost:8443/realms/master

# Reapply network policies
kubectl apply -f security/network-policies.yaml
```

## 🔧 Advanced Debugging

### Debug Keycloak Configuration

```bash
# Access Keycloak container
kubectl exec -it deployment/keycloak -n keycloak -- bash

# Check Keycloak configuration
cat /opt/keycloak/conf/keycloak.conf

# Check environment variables
env | grep KC_

# Test database connection from within container
psql -h postgres -U keycloak -d keycloak
```

### Debug Network Connectivity

```bash
# Test pod-to-pod communication
kubectl exec -it deployment/keycloak -n keycloak -- nslookup postgres

# Test external connectivity
kubectl exec -it deployment/keycloak -n keycloak -- curl -I https://google.com

# Check network policies
kubectl get networkpolicies -n keycloak
kubectl describe networkpolicy keycloak-network-policy -n keycloak
```

### Debug Storage Issues

```bash
# Check volume mounts
kubectl describe pod -l app=keycloak -n keycloak

# Check persistent volumes
kubectl get pv
kubectl get pvc -n keycloak

# Check disk usage
kubectl exec -it deployment/postgres -n keycloak -- df -h
```

## 🚀 Performance Troubleshooting

### Slow Startup Times

**Check Resource Constraints:**
```bash
kubectl top pods -n keycloak
kubectl describe pod -l app=keycloak -n keycloak | grep -A 5 "Limits"
```

**Increase Resources:**
```go
// In main.go, increase resource limits
Resources: &corev1.ResourceRequirementsArgs{
    Limits: pulumi.StringMap{
        "memory": pulumi.String("2Gi"),
        "cpu":    pulumi.String("2000m"),
    },
    Requests: pulumi.StringMap{
        "memory": pulumi.String("1Gi"),
        "cpu":    pulumi.String("1000m"),
    },
},
```

### High Memory Usage

```bash
# Monitor memory usage
kubectl top pods -n keycloak
watch kubectl top pods -n keycloak

# Check for memory leaks
kubectl exec -it deployment/keycloak -n keycloak -- \
  jcmd $(pgrep java) VM.summary
```

## 🔍 Log Analysis

### Useful Log Commands

```bash
# Real-time logs
kubectl logs -f deployment/keycloak -n keycloak

# Logs from all containers
kubectl logs -f -l app=keycloak -n keycloak --all-containers

# Previous container logs (after crash)
kubectl logs deployment/keycloak -n keycloak --previous

# Filter logs
kubectl logs deployment/keycloak -n keycloak | grep ERROR
kubectl logs deployment/keycloak -n keycloak | grep -i "database"
```

### Common Log Patterns

**Successful Startup:**
```
INFO  [org.keycloak.services] (main) KC-SERVICES0050: Initializing master realm
INFO  [io.quarkus] (main) Keycloak 23.0.0 on JVM started in 15.234s
INFO  [io.quarkus] (main) Profile prod activated
INFO  [io.quarkus] (main) Installed features: [cdi, hibernate-orm, jdbc-postgres, ...]
```

**Database Connection Success:**
```
INFO  [org.hibernate.dialect.Dialect] (JPA Startup Thread) HHH000400: Using dialect: org.hibernate.dialect.PostgreSQLDialect
INFO  [org.hibernate.engine.transaction.jta.platform.internal.JBossStandAloneJtaPlatform]
```

**TLS Configuration Success:**
```
INFO  [io.quarkus.vertx.http.deployment.devmode.VertxHttpDevModeConfig] HTTPS enabled, using certificate
```

## 📊 Monitoring Setup

### Basic Monitoring

```bash
# Watch pod status
watch kubectl get pods -n keycloak

# Monitor resource usage
watch kubectl top pods -n keycloak

# Monitor events
kubectl get events -w -n keycloak
```

### Health Endpoints

```bash
# Keycloak health check
curl -k https://keycloak.local:8443/health

# Realm discovery
curl -k https://keycloak.local:8443/realms/master/.well-known/openid_configuration

# Admin API health
curl -k https://keycloak.local:8443/admin/
```

## 🧹 Recovery Procedures

### Complete Reset

```bash
# Full cleanup and redeploy
make cleanup
make deploy
```

### Partial Reset

```bash
# Reset only Keycloak (preserve database)
kubectl delete deployment keycloak -n keycloak
pulumi up --yes

# Reset only database (will lose data)
kubectl delete deployment postgres -n keycloak
pulumi up --yes
```

### Backup and Restore

```bash
# Backup database
kubectl exec -it deployment/postgres -n keycloak -- \
  pg_dump -U keycloak keycloak > keycloak-backup.sql

# Restore database
cat keycloak-backup.sql | kubectl exec -i deployment/postgres -n keycloak -- \
  psql -U keycloak keycloak
```

## 📞 Getting Help

### Information to Gather

When seeking help, collect this information:

```bash
# System info
kubectl version
kubectl cluster-info
go version
pulumi version

# Deployment status
kubectl get all -n keycloak
kubectl get events -n keycloak

# Logs
kubectl logs deployment/keycloak -n keycloak --tail=50
kubectl logs deployment/postgres -n keycloak --tail=50

# Pulumi state
pulumi stack output --json
```

### Useful Resources

- **[Keycloak Community](https://github.com/keycloak/keycloak/discussions)**
- **[Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)**
- **[Pulumi Community](https://slack.pulumi.com/)**
- **[Docker Desktop Issues](https://docs.docker.com/desktop/troubleshoot/)**

### Emergency Procedures

**If everything is broken:**
```bash
# Nuclear option: destroy everything
./scripts/cleanup.sh
kind delete cluster --name keycloak-cluster  # if using kind
docker system prune -a
./setup.sh
```

**If cluster is unresponsive:**
```bash
# Reset Kubernetes cluster
# For Rancher Desktop: Settings → Reset Kubernetes
# For kind: kind delete cluster --name keycloak-cluster && ./setup.sh
# For minikube: minikube delete && ./setup.sh
```

Remember: This is a development environment, so data loss is acceptable for troubleshooting purposes!
