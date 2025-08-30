# Docker Vaultwarden Tailscale Architecture

This repository implements a sophisticated self-hosted password manager setup that provides both public and private network access through intelligent DNS routing and mesh networking.

## Architecture Overview

This setup creates a secure, multi-path access system for Vaultwarden (a Bitwarden-compatible password manager) using Tailscale for private network access and Caddy for public reverse proxy functionality with split-horizon DNS.

## Component Overview

### Core Services

1. **Vaultwarden** - Bitwarden-compatible password manager server
2. **Caddy** - Reverse proxy with automatic HTTPS and Cloudflare DNS integration
3. **Tailscale** - WireGuard-based mesh VPN for secure private access
4. **dnsmasq** - DNS resolver for split-horizon functionality
5. **cron** - Automated backup system with encryption and remote storage

## Network Architecture Diagrams

### High-Level Network Flow

```
                    ┌─────────────────────────────────────────┐
                    │              Internet               │
                    └─────────────┬───────────────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │      Cloudflare DNS/CDN      │
                    │   (TLS Certificate & DDNS)   │
                    └─────────────┬────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │        GCP Firewall          │
                    │    (Static IP Whitelist)     │
                    └─────────────┬────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │          Caddy               │
                    │    (Reverse Proxy)          │
                    │    Port 443 HTTPS           │
                    └─────────────┬────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │       Vaultwarden            │
                    │     (Password Manager)       │
                    │       Port 80 HTTP          │
                    └──────────────────────────────┘
```

### Tailscale Private Network Flow

```
    ┌──────────────┐         ┌─────────────────────┐         ┌──────────────┐
    │   Client     │◄────────┤    Tailscale Mesh   ├────────►│ GCP Instance │
    │  (Tailscale  │         │      Network        │         │              │
    │   Enabled)   │         │   (WireGuard VPN)   │         │              │
    └──────────────┘         └─────────────────────┘         └──────┬───────┘
           │                                                         │
           │ DNS Query: vaultwarden.example.com                     │
           │                                                         │
           ▼                                                         ▼
    ┌──────────────┐                                         ┌──────────────┐
    │   dnsmasq    │◄────────────────────────────────────────┤  Tailscale   │
    │ (Split DNS)  │         Tailscale IP: 100.x.x.x         │   Daemon     │
    └──────┬───────┘                                         └──────┬───────┘
           │                                                         │
           │ Returns: 100.x.x.x                                     │
           │                                                         ▼
           ▼                                                 ┌──────────────┐
    ┌──────────────┐                                         │    Caddy     │
    │   Client     │─────────────────────────────────────────┤              │
    │              │         Direct Tailscale               │              │
    │              │         Connection                       └──────┬───────┘
    └──────────────┘         (Encrypted)                            │
                                                                    ▼
                                                            ┌──────────────┐
                                                            │ Vaultwarden  │
                                                            └──────────────┘
```

### Container Network Architecture

```
Docker Host (GCP Instance)
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │     dnsmasq     │  │   Tailscale     │  │     Caddy       │         │
│  │  (DNS Server)   │  │  (VPN Client)   │  │ (Reverse Proxy) │         │
│  │                 │  │                 │  │                 │         │
│  │ Network Mode:   │  │ Network Mode:   │  │ Network:        │         │
│  │ service:        │  │ service:caddy   │  │ caddy           │         │
│  │ tailscale       │  │                 │  │ Port: 443       │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│           │                     │                     │                 │
│           │                     │                     │                 │
│           └─────────────────────┼─────────────────────┘                 │
│                                 │                                       │
│  ┌─────────────────┐            │          ┌─────────────────┐         │
│  │   Vaultwarden   │◄───────────┼──────────┤      cron       │         │
│  │ (Password Mgr)  │            │          │   (Backups)     │         │
│  │                 │            │          │                 │         │
│  │ Network:        │            │          │ Network: cron   │         │
│  │ caddy           │            │          │                 │         │
│  │ Port: 80        │            │          │                 │         │
│  └─────────────────┘            │          └─────────────────┘         │
│                                 │                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Shared Volumes                            │   │
│  │                                                               │   │
│  │  • hosts: Tailscale IP mappings (tailscale ↔ dnsmasq)       │   │
│  │  • vaultwarden-data: Password database (vaultwarden ↔ cron)  │   │
│  │  • caddy-data: TLS certificates                              │   │
│  │  • tailscale-data: VPN state and config                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Split-Horizon DNS Resolution

```
┌───────────────────────────┐
│      Client Request.      │
│ vaultwarden.example.com   │
└──────────┬────────────────┘
           │
           ▼
    ┌─────────────┐
    │   Client    │
    │   Status?   │
    └─────┬───┬───┘
          │   │
    ┌─────▼─┐ └──────▼──┐
    │Tailscale    │No Tailscale│
    │Enabled │    │Connection │
    └─────┬───┘    └────┬─────┘
          │             │
          ▼             ▼
    ┌─────────────┐ ┌─────────────┐
    │   dnsmasq   │ │Public DNS   │
    │(Tailscale IP│ │ Resolver    │
    │ 100.x.x.x)  │ │             │
    └─────┬───────┘ └─────┬───────┘
          │               │
          │               │
          ▼               ▼
    ┌─────────────┐ ┌─────────────┐
    │ Direct VPN  │ │   Public    │
    │ Connection  │ │ Internet    │
    │(Encrypted)  │ │ Connection  │
    └─────┬───────┘ └─────┬───────┘
          │               │
          └───────┬───────┘
                  │
                  ▼
          ┌───────────────┐
          │  Vaultwarden  │
          │  (Same App)   │
          └───────────────┘
```

## Network Modes and Container Relationships

### Network Mode: service:caddy
- **Tailscale Container**: Shares Caddy's network namespace
- **Effect**: Tailscale traffic appears to come from Caddy container
- **Benefit**: Simplifies routing and reduces network complexity

### Network Mode: service:tailscale  
- **dnsmasq Container**: Shares Tailscale's network namespace
- **Effect**: DNS server accessible on Tailscale network
- **Benefit**: Provides split-horizon DNS functionality

### Isolated Networks
- **caddy network**: Caddy ↔ Vaultwarden communication
- **cron network**: Backup operations isolated from web traffic

## Data Flow Analysis

### Known Location Access Flow (IP-Restricted Public Path)
1. **DNS Resolution**: vaultwarden.example.com → Public IP (via Cloudflare)
2. **Firewall**: GCP firewall validates source IP against whitelist (CRITICAL: Only whitelisted IPs allowed)
3. **TLS Termination**: Caddy handles HTTPS with Cloudflare DNS challenge
4. **Proxy**: Caddy forwards to vaultwarden.dc:80
5. **Response**: Encrypted vault data returned via HTTPS

**SECURITY NOTE**: This path requires firewall IP restrictions and is intended only for access from known, trusted locations (e.g., home network with static IP).

### Private Access Flow (Tailscale Users)
1. **DNS Resolution**: vaultwarden.example.com → Tailscale IP (via dnsmasq)
2. **VPN Routing**: Traffic routed through Tailscale mesh network
3. **Local Proxy**: Caddy on Tailscale network handles request
4. **Internal Routing**: Request forwarded to vaultwarden.dc:80
5. **Response**: Encrypted vault data returned via Tailscale VPN

### Backup Flow (Automated)
1. **Schedule**: Cron executes daily backup script
2. **Database Backup**: SQLite database backed up with .backup command
3. **File Copy**: Attachments and config files copied
4. **Compression**: Data compressed with tar/xz
5. **Encryption**: GPG encryption with passphrase
6. **Upload**: Encrypted backup sent to remote storage via rclone
7. **Cleanup**: Old backups pruned locally and remotely

## Security Model

### Multi-Layer Security
1. **Application Layer**: Vaultwarden client-side encryption
2. **Transport Layer**: HTTPS/TLS for public access, WireGuard for private
3. **Network Layer**: GCP firewall rules and Tailscale ACLs
4. **DNS Layer**: Split-horizon prevents DNS leaks
5. **Data Layer**: Encrypted backups with GPG

### Access Control Matrix
```
┌─────────────────┬────────────────┬─────────────────┬─────────────────┐
│ Access Method   │ Network Path   │ Authentication  │ Encryption      │
├─────────────────┼────────────────┼─────────────────┼─────────────────┤
│ Known Location  │ Cloudflare     │ IP Whitelist +  │ HTTPS + E2E     │
│ (IP Restricted) │ → GCP FW (IPs) │ Bitwarden Login │                 │
│                 │ → Caddy        │                 │                 │
├─────────────────┼────────────────┼─────────────────┼─────────────────┤
│ Tailscale VPN   │ Mesh Network   │ Tailscale Auth  │ WireGuard +     │
│                 │ → dnsmasq      │ + Bitwarden     │ HTTPS + E2E     │
│                 │ → Caddy        │ Login           │                 │
└─────────────────┴────────────────┴─────────────────┴─────────────────┘
```

This architecture provides robust security through multiple independent layers while maintaining accessibility through intelligent routing based on client network status.