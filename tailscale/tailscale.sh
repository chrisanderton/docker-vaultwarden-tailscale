#!/bin/ash

if [ "${DEBUG:=false}" = true ]; then set -x; fi

# format with timestamp; not using as docker already timestamps
# if using this, need to add -1 as first arg to printf to use 'now'
# : ${LOG_FORMAT:="[%(%Y-%m-%dT%H:%M:%S:%z)T] - %s: %s"}

# first string is script name, other args passed thereafter
: ${LOG_FORMAT:="%s: %s\n"}
out() {
  printf "${LOG_FORMAT}" "$(basename $0)" "$*"
}

err() {
  out "$*" >&2
}

out "Starting TS daemon"
tailscaled --tun=userspace-networking &

sleep 3

out "Connecting to network"
tailscale up --authkey=${AUTH_KEY} "$@"

sleep 3

# can also access local api via curl --unix-socket /run/tailscale/tailscaled.sock http://localhost/localapi/v0/status
while true; do 
  if tailscale_ip=$(tailscale ip -4); then
    out "Tailscale IP:" "${tailscale_ip}"
    printf "%s %s" "${tailscale_ip}" "${FQDN}" > /etc/host/tailscale
  else
    err "Could not get tailscale IP"
  fi

  tailscale status
  sleep 3600
done &

sleep infinity
