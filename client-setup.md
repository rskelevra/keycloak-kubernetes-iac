# Client Application Setup Guide

This guide explains how to configure client applications to work with your Keycloak deployment.

## Quick Setup

### 1. Access Admin Console

1. Navigate to: https://keycloak.local:8443/admin/
2. Login with admin credentials (shown after deployment)
3. Select "Master" realm or create a new realm

### 2. Create a New Realm (Recommended)

```bash
# Using the demo realm configuration
kubectl exec -it deployment/keycloak -n keycloak -- \
  /opt/keycloak/bin/kc.sh import --file /opt/keycloak/data/import/demo-realm.json
```

Or via Admin Console:
1. Click "Add realm" (hover over realm dropdown)
2. Name: `demo-realm`
3. Click "Create"

### 3. Create Client Application

#### Via Admin Console:
1. Go to "Clients" → "Create"
2. Client ID: `my-app`
3. Client Protocol: `openid-connect`
4. Root URL: `http://localhost:3000`
5. Click "Save"

#### Client Configuration:
```json
{
  "clientId": "my-app",
  "enabled": true,
  "publicClient": false,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "redirectUris": ["http://localhost:3000/*"],
  "webOrigins": ["http://localhost:3000"],
  "baseUrl": "http://localhost:3000"
}
```

### 4. Create Test User

1. Go to "Users" → "Add user"
2. Username: `testuser`
3. Email: `test@example.com`
4. Click "Save"
5. Go to "Credentials" tab
6. Set password: `password123`
7. Set "Temporary" to OFF
8. Click "Set Password"

## Integration Examples

### JavaScript/Node.js

```javascript
const Keycloak = require('keycloak-js');

const keycloak = new Keycloak({
  url: 'https://keycloak.local:8443',
  realm: 'demo-realm',
  clientId: 'my-app'
});

// Initialize
keycloak.init({
  onLoad: 'login-required',
  checkLoginIframe: false
}).then((authenticated) => {
  console.log(authenticated ? 'Authenticated' : 'Not authenticated');
});
```

### cURL Examples

```bash
# Get access token
curl -k -X POST https://keycloak.local:8443/realms/demo-realm/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=my-app" \
  -d "username=testuser" \
  -d "password=password123"

# Verify token
curl -k -X POST https://keycloak.local:8443/realms/demo-realm/protocol/openid-connect/token/introspect \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "token=YOUR_ACCESS_TOKEN" \
  -d "client_id=my-app"
```

### Python

```python
from keycloak import KeycloakOpenID

# Configure client
keycloak_openid = KeycloakOpenID(
    server_url="https://keycloak.local:8443",
    client_id="my-app",
    realm_name="demo-realm",
    verify=False  # For self-signed certificates
)

# Get token
token = keycloak_openid.token(username="testuser", password="password123")
print(token)

# Get user info
userinfo = keycloak_openid.userinfo(token['access_token'])
print(userinfo)
```

### React Application

```jsx
import { ReactKeycloakProvider } from '@react-keycloak/web';
import Keycloak from 'keycloak-js';

const keycloak = new Keycloak({
  url: 'https://keycloak.local:8443',
  realm: 'demo-realm',
  clientId: 'my-app'
});

function App() {
  return (
    <ReactKeycloakProvider authClient={keycloak}>
      <YourAppComponents />
    </ReactKeycloakProvider>
  );
}
```

## Advanced Configuration

### Single Sign-On (SSO)

1. Create multiple client applications
2. Users logged into one app are automatically logged into others
3. Configure shared session settings

### Social Login

1. Go to "Identity Providers"
2. Add provider (Google, GitHub, etc.)
3. Configure OAuth credentials
4. Test integration

### Custom Themes

```bash
# Copy theme files to Keycloak
kubectl cp ./custom-theme keycloak-pod:/opt/keycloak/themes/

# Update realm theme settings
# Admin Console → Realm Settings → Themes
```

### SAML Integration

1. Create SAML client
2. Configure SAML settings
3. Download metadata
4. Configure SP (Service Provider)

## Security Best Practices

### Client Security

1. **Use PKCE** for public clients
2. **Validate redirect URIs** strictly
3. **Use short-lived tokens** (5-15 minutes)
4. **Implement proper logout**

### Token Handling

```javascript
// Good: Store tokens securely
localStorage.removeItem('token'); // Clear on logout
sessionStorage.setItem('refresh_token', token);

// Better: Use httpOnly cookies when possible
document.cookie = "access_token=; expires=Thu, 01 Jan 1970 00:00:00 GMT";
```

### Network Security

1. **Always use HTTPS** in production
2. **Implement CORS** properly
3. **Use proper certificates** (not self-signed)
4. **Monitor token usage**

## Troubleshooting

### Common Issues

**Invalid redirect URI:**
```
Solution: Add exact URL to client's redirect URIs
Location: Clients → [your-client] → Settings → Valid Redirect URIs
```

**CORS errors:**
```
Solution: Add origins to Web Origins
Location: Clients → [your-client] → Settings → Web Origins
```

**Certificate errors:**
```bash
# Temporary: Accept self-signed certificate
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Production: Use proper certificates
kubectl create secret tls keycloak-tls --cert=cert.pem --key=key.pem
```

### Token Debugging

```bash
# Decode JWT token (use jwt.io)
echo "TOKEN_HERE" | base64 -d

# Check token validity
curl -k -X GET https://keycloak.local:8443/realms/demo-realm/protocol/openid-connect/userinfo \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Testing

### Health Check

```bash
# Test realm endpoint
curl -k https://keycloak.local:8443/realms/demo-realm

# Test admin endpoints
curl -k https://keycloak.local:8443/admin/realms/demo-realm
```

### Load Testing

```bash
# Simple load test with ab
ab -n 100 -c 10 -k https://keycloak.local:8443/realms/demo-realm
```

## Next Steps

1. **Production Setup**: Use proper certificates and external database
2. **Monitoring**: Set up Prometheus/Grafana monitoring
3. **Backup**: Implement database backup strategy
4. **Scaling**: Configure cluster mode for high availability
5. **Security**: Regular security audits and updates

## Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Admin Console Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Client Adapters](https://www.keycloak.org/docs/latest/securing_apps/)
- [REST API Reference](https://www.keycloak.org/docs-api/latest/rest-api/)
