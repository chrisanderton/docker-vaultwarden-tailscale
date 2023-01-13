#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

if [ "${DEBUG:=false}" = true ]; then set -x; fi

: "${LOG_FORMAT:=%s: %s\n}"

# Cloudflare TTL for record, between 120 and 86400 seconds
: "${DDNS_RECORD_TTL:=120}"

# Ignore local file, update ip anyway
: "${DDNS_FORCE_UPDATE:=false}"

: "${IP_LOOKUP_URL:=http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip}"
: "${IP_LOOKUP_HEADERS:=Metadata-Flavor: Google}"

# first string is script name, other args passed thereafter
out() {
  printf "${LOG_FORMAT}" "$(basename $0)" "$*"
}

err() {
  out "$*" >&2
}

if [[ -z "${CLOUDFLARE_API_KEY:=}" ]]; then err "CLOUDFLARE_API_KEY missing" && exit 101; fi
if [[ -z "${DDNS_ZONE:=}" ]]; then err "DDNS_ZONE missing" && exit 102; fi
if [[ -z "${DDNS_HOSTNAME:=}" ]]; then err "DDNS_HOSTNAME missing" && exit 102; fi

# Get current and old WAN ip
out "Fetching IP"
wan_ip=$(curl -s -H "${IP_LOOKUP_HEADERS}" "${IP_LOOKUP_URL}")
wan_ip_cache_file=$HOME/.wan_ip_$DDNS_HOSTNAME.txt
if [ -f "$wan_ip_cache_file" ]; then
  wan_ip_cache=$(cat "$wan_ip_cache_file")
fi

out "IP: $wan_ip"

if [ "$wan_ip" = "${wan_ip_cache:-}" ] && [ "$DDNS_FORCE_UPDATE" = false ]; then
  out "No update required (cached IP is current IP)"
  exit 0
fi

cloudflare_id_file=$HOME/.cloudflare_$DDNS_HOSTNAME.json

if [ -f "$cloudflare_id_file" ]; then 
  read -r -d '' cloudflare_zone cloudflare_hostname cloudflare_zone_id cloudflare_record_id < <(jq -r '.zone, .hostname, .zone_id, .record_id' "$cloudflare_id_file") || true
fi
  
if [ ! -f "$cloudflare_id_file" ] || [ "$cloudflare_zone" != "$DDNS_ZONE" ] || [ "$cloudflare_hostname" != "$DDNS_HOSTNAME" ]; then
  out "Updating cached Cloudflare IDs"
  cloudflare_zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DDNS_ZONE" -H "Authorization: Bearer $CLOUDFLARE_API_KEY" -H "Content-Type: application/json" | jq -r '.result[].id' | head -1 )
  cloudflare_record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone_id/dns_records?name=$DDNS_HOSTNAME.$DDNS_ZONE" -H "Authorization: Bearer $CLOUDFLARE_API_KEY" -H "Content-Type: application/json"  | jq -r '.result[].id' | head -1 )

  : $(jq --null-input \
         --arg zone "$DDNS_ZONE" \
         --arg hostname "$DDNS_HOSTNAME" \
         --arg zone_id "$cloudflare_zone_id" \
         --arg record_id "$cloudflare_record_id" \
         '{"zone": $zone, "hostname": $hostname, "zone_id": $zone_id, "record_id": $record_id}' \
         > "$cloudflare_id_file"
  )
fi

: "${cloudflare_zone:=$DDNS_ZONE}"
: "${cloudflare_hostname:=$DDNS_HOSTNAME}"

out "Zone: $cloudflare_zone"
out "Hostname: $cloudflare_hostname"
out "Zone ID: $cloudflare_zone_id"
out "Record ID: $cloudflare_record_id"
out "Updating DNS to $wan_ip"

put_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone_id/dns_records/$cloudflare_record_id" \
  -H "Authorization: Bearer $CLOUDFLARE_API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$cloudflare_zone_id\",\"type\":\"A\",\"name\":\"$cloudflare_hostname\",\"content\":\"$wan_ip\", \"ttl\":$DDNS_RECORD_TTL}" \
  | jq -r '.success'
)

if [ "$put_response" == "true" ]; then
  out "Cloudflare Updated"
  echo "$wan_ip" > "$wan_ip_cache_file"
  exit
else
  err "Error updating Cloudflare: $put_response"
  exit 1
fi
