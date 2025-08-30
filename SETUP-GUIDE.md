# Setup Guide: Docker Vaultwarden with Tailscale

This guide explains how to deploy and configure this sophisticated self-hosted password manager setup.

## What This Setup Achieves

This architecture creates a **dual-access password manager** that provides:

1. **Known Location Access**: HTTPS access from trusted, whitelisted IP addresses (NOT open public access)
2. **Private VPN Access**: Secure, encrypted access via Tailscale mesh network
3. **Intelligent Routing**: Automatic selection between public/private based on client status
4. **Zero-Config Security**: Automatic HTTPS certificates and VPN mesh networking
5. **Automated Backups**: Encrypted backups to remote storage with retention management

## Prerequisites

### Required Services
- **GCP Instance** (or similar cloud provider)
- **Cloudflare Account** with domain management
- **Tailscale Account** with auth keys
- **Remote Storage** (AWS S3, Google Cloud Storage, etc.) for backups

### Required Information
- Domain name managed by Cloudflare
- Static IP address for your home network
- Tailscale auth key for device registration
- Cloud storage credentials for backups

## Environment Configuration

The setup uses multiple environment files for different concerns:

### `.env.host` - Domain and networking
```bash
FQDN=vaultwarden.example.com
DDNS_ZONE=example.com
DDNS_HOSTNAME=vaultwarden
```

### `.env.cloudflare` - DNS and certificates
```bash
CLOUDFLARE_API_KEY=your_cloudflare_api_token
```

### `.env.tailscale` - VPN configuration
```bash
AUTH_KEY=tskey-auth-your_tailscale_auth_key
```

### `.env.vaultwarden` - Password manager settings
```bash
DOMAIN=https://vaultwarden.example.com
ADMIN_TOKEN=your_secure_admin_token
SMTP_HOST=smtp.gmail.com
SMTP_FROM=your-email@gmail.com
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your_app_password
```

### `.env.email` - Certificate email
```bash
EMAIL=your-email@example.com
```

### `.env.aws` (Optional) - Backup storage
```bash
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

### `.env.backup` (Optional) - Backup configuration
```bash
VAULTWARDEN_DATA=/vaultwarden/data
BACKUP_DATA=/backup
GPG_PASSPHRASE=your_secure_passphrase
RCLONE_REMOTE=s3:your-backup-bucket
RCLONE_ARGS=--config /dev/null
LOCAL_BACKUP_PRUNE_DAYS=7
REMOTE_BACKUP_PRUNE_DAYS=30
```

## Deployment Steps

### 1. Clone and Configure
```bash
git clone <this-repository>
cd docker-vaultwarden-tailscale
```

### 2. Create Environment Files
Create all the environment files listed above with your specific values.

### 3. GCP Firewall Configuration
```bash
# CRITICAL SECURITY STEP: Allow HTTPS from your home IP ONLY
# Replace YOUR_STATIC_IP with your actual static IP address
gcloud compute firewall-rules create allow-vault-https \
    --allow tcp:443 \
    --source-ranges YOUR_STATIC_IP/32 \
    --description "Allow HTTPS access to Vaultwarden from home"
```

**WARNING**: Without this firewall rule, the service will be inaccessible from known locations. With an overly permissive rule (e.g., 0.0.0.0/0), the service becomes publicly accessible to the entire internet, which defeats the security model.

### 4. Cloudflare Configuration
- Add A record for your domain pointing to GCP instance IP
- Generate API token with `Zone:DNS:Edit` permissions
- Enable "Proxy status" (orange cloud) for the domain

### 5. Deploy Services
```bash
docker-compose up -d
```

### 6. Verify Deployment
```bash
# Check all services are running
docker-compose ps

# Check Tailscale connection
docker-compose exec tailscale tailscale status

# Check DNS resolution
docker-compose exec dnsmasq nslookup vaultwarden.example.com

# Check Caddy logs for certificate acquisition
docker-compose logs caddy
```

## Access Configuration

### Setting Up Split DNS in Tailscale Admin

1. Navigate to Tailscale Admin Console → DNS
2. Enable "Override local DNS"
3. Add custom nameserver: `100.x.x.x` (your container's Tailscale IP)
4. Set search domains to include your domain
5. Configure restricted nameservers:
   ```
   vaultwarden.example.com = 100.x.x.x
   ```

### Client Configuration

#### For Tailscale Users:
1. Install Tailscale on client devices
2. Connect to your Tailscale network
3. Access `https://vaultwarden.example.com` - should resolve to Tailscale IP
4. Traffic flows entirely through VPN mesh network

#### For Known Location Users (whitelisted IPs):
1. Access `https://vaultwarden.example.com` from whitelisted IP addresses only
2. Traffic flows through Cloudflare → GCP Firewall → Caddy
3. **CRITICAL**: Only works from pre-configured, trusted IP addresses (e.g., home network)
4. Intended for use when you're at known, secure locations but don't want to use Tailscale

## How It Works

### Network Path Selection

The system automatically selects the optimal network path based on client capabilities:

```
Client Request: https://vaultwarden.example.com

┌─── Tailscale Enabled ───┐    ┌── Tailscale Disabled ──┐
│                         │    │                        │
│ DNS Query → dnsmasq     │    │ DNS Query → Public DNS │
│ Response: 100.x.x.x     │    │ Response: Public IP    │
│                         │    │                        │
│ Route: Mesh VPN         │    │ Route: Internet        │
│ Security: WireGuard +   │    │ Security: IP Filter +  │
│           HTTPS + E2E   │    │          HTTPS + E2E   │
└─────────────────────────┘    └────────────────────────┘
                    │                         │
                    └──── Same Application ───┘
                         (Vaultwarden)
```

### Container Network Topology

1. **Caddy** (Primary Network): Handles all external connections
2. **Tailscale** (Network Mode: service:caddy): Shares Caddy's network stack
3. **dnsmasq** (Network Mode: service:tailscale): Provides DNS on VPN network
4. **Vaultwarden** (Internal Network): Only accessible via Caddy proxy
5. **cron** (Isolated Network): Backup operations separate from web traffic

## Security Features

### Multi-Layer Protection
- **L7 (Application)**: Bitwarden end-to-end encryption
- **L4 (Transport)**: HTTPS/TLS and WireGuard encryption  
- **L3 (Network)**: GCP firewall and Tailscale ACLs
- **L2 (DNS)**: Split-horizon prevents information disclosure
- **L1 (Data)**: Encrypted backups with GPG

### Zero Trust Principles
- Default deny for all network access
- Every connection authenticated and encrypted
- Minimal attack surface through network isolation
- Comprehensive audit logging

## Maintenance

### Monitoring
```bash
# Check service health
docker-compose ps

# Monitor backup operations
docker-compose logs cron

# View access logs
docker-compose logs caddy

# Check Tailscale connectivity
docker-compose exec tailscale tailscale status
```

### Updates
```bash
# Update container images
docker-compose pull
docker-compose up -d

# View recent changes
git log --oneline -10
```

### Backup Verification
```bash
# List local backups
ls -la ./backup-data/

# Test backup restoration (in development environment)
docker run --rm -v backup-data:/backup alpine \
  sh -c "cd /backup && gpg -d vaultwarden-YYYYMMDD-HHMM.tar.xz.gpg | tar -tf -"
```

## Troubleshooting

### Common Issues

#### DNS Resolution Problems
```bash
# Test external DNS
nslookup vault.example.com 8.8.8.8

# Test internal DNS
docker-compose exec dnsmasq nslookup vaultwarden.example.com

# Check host file updates
docker-compose exec tailscale cat /etc/host/tailscale
```

#### Certificate Issues
```bash
# Check certificate status
docker-compose exec caddy caddy list-certificates

# Force certificate renewal
docker-compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

#### Tailscale Connectivity
```bash
# Check Tailscale status
docker-compose exec tailscale tailscale status

# View Tailscale logs
docker-compose logs tailscale

# Test Tailscale connectivity
docker-compose exec tailscale tailscale ping <peer-ip>
```

### Log Analysis
```bash
# All service logs
docker-compose logs

# Specific service logs
docker-compose logs -f caddy
docker-compose logs -f tailscale
docker-compose logs -f vaultwarden
```

## Benefits of This Architecture

### Security Benefits
- **Zero Trust Network**: Every connection authenticated and encrypted
- **Defense in Depth**: Multiple security layers with independent failure modes
- **Minimal Attack Surface**: Only necessary ports exposed with IP restrictions
- **Secure Backup**: Encrypted backups with automated rotation

### Operational Benefits  
- **High Availability**: Multiple access paths prevent single points of failure
- **Automatic Maintenance**: Self-renewing certificates and automated backups
- **Network Transparency**: Same application accessible via multiple paths
- **Simple Management**: Single docker-compose file manages entire stack

### User Experience Benefits
- **Seamless Access**: Automatic path selection based on client capabilities
- **Performance**: Direct VPN connections bypass internet routing
- **Reliability**: Fallback access methods ensure availability
- **Security**: Enhanced privacy through VPN mesh networking

This setup represents a production-ready, secure, and maintainable approach to self-hosted password management with intelligent network routing.