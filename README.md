# docker-vaultwarden-tailscale
Docker compose for Vaultwarden with Tailscale (and split horizon DNS) with Caddy (and Cloudflare DNS TLS) running on GCP.

I have one hostname for Vaultwarden that allows for both modes of access: 
- people on the home network can access Vaultwarden without Tailscale; GCP firewall is configured for ingress from my static IP
- outside of the home network, people can only access Vaultwarden over Tailscale

## cron (optional: if you don't need Cloudflare DDNS or backups you can comment this out)

The cron container is based on a [simple image](https://githubc.com/chrisanderton/docker-crond) that exposes cron from Alpine and a few utilities. You can supply a crontab file to the environment, or simply mount files to the relevant cron directory.

`./cron/cloudflare.sh` is mounted and run every 5 minutes. This is a basic DDNS script for Cloudflare to set the IP of the specified hostname to the public IP address of the GCP instance. If you're not looking to access the instance outside of Tailscale, or are not using Cloudflare you can comment this out.

`./cron/vaultwarden-backup.sh` is mounted and run daily. This is another basic script that uses rclone to take a backup of the Vaultwarden data (which is also mounted to the cron container as a read-only volume). Rclone configuration is passed in the environment; the example is using AWS as the backup target.

## dnsmasq

Uses a [dnsmasq](https://github.com/chrisanderton/docker-dnsmasq) image to provide a simple DNS resolver. Runtime configuration can be sent as the command in the compose file. 

In this example we mount a read-only Docker volume to `/etc/host` and have dnsmasq watch for changes so it will always serve the latest data. Requests that are not resolved are sent on to Cloudflare for resolution.

The dnsmasq container is bolted on the side of the Tailscale container and allows for the split horizon DNS. The Tailscale entrypoint populates a file in the `hosts` volume with the Tailscale IP and maps this to the hostname for Vaultwarden (`FQDN`). In turn, this is read and served by dnsmasq, such that queries to the local DNS server resolve to the Tailscale IP.

The last piece of the puzzle is to set the Split DNS option in Tailscale itself and Override DNS. Set the search domain as appropriate and set the DNS to point to the Tailscale IP of the Docker container.

With Tailscale disabled, DNS will resolve to the public IP address.

With Tailscale enabled, DNS will resolve over Tailscale to the Tailscale IP address.

## vaultwarden

This one is thankfully simple - normal Vaultwarden configuration.

## caddy

Also a pretty vanilla caddy setup; main difference is using DNS based ACME setup. My DNS is managed with Cloudflare, it's pretty straightforward to use DNS-based ACME with the other plugins available if needed.

## tailscale

Bolted on the side of caddy, running in usermode with no elevated privileges.


## Other considerations

1. I made some custom images and scripts for cron, dnsmasq, ddns and backups. Others do exist and I played with some of them, but couldn't get them to work how I wanted. If people have a better, simpler alternative, let me know.

2. I'm not hugely comfortable having Caddy and Tailscale glued together. It feels like there is some risk in having Tailscale (which is a path to my home network) accessible from Caddy which is exposed externally. Mitigation is that I have ingress quite tightly controlled but I couldn't find a better way.

  * I looked at _serve_ and the proxy options, but they can only proxy from Tailscale to 127.0.0.1 at present. I didn't want to run multiple processes in the Tailscale container (it would mean running a proxy to a proxy to caddy.. too many levels)
  * I think pull requests [like this](https://github.com/tailscale/tailscale/pull/6521) might remove some of the limitations on serve. If implemented, Tailscale could proxy directly to Caddy without needing to be bolted on the side.
  * I looked at [https://github.com/markpash/tailscale-sidecar](tailscale-sidecar) and some other projects that looked like a good fit.. but I couldn't get them working (probably me, not them)
  
3. The main complexity in my setup is the split-DNS approach. If I only wanted to access Vaultwarden over Tailscale the setup would be far simpler.
