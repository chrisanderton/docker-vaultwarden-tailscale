#!/usr/bin/env bash

set -e
if [ "${DEBUG:=false}" = true ]; then set -x; fi

: "${LOG_FORMAT:=%s: %s\n}"
: "${GPG_ALGORITHM:=AES128}"
: "${BACKUP_BASENAME=vaultwarden-}" 
: "${DB_FILE:=db.sqlite3}"

backup_filename=$(printf '%s/%s%s.%s' "${BACKUP_DATA}" "${BACKUP_BASENAME}" "$(date '+%Y%m%d-%H%M')" "tar.xz")

# first string is script name, other args passed thereafter
out() {
  printf "${LOG_FORMAT}" "$(basename $0)" "$*"
}

err() {
  out "$*" >&2
}

if [[ -z "${VAULTWARDEN_DATA:=}" ]] || [[ ! -d "${VAULTWARDEN_DATA:=}" ]]; then err "VAULTWARDEN_DATA missing" && exit 101; fi
if [[ -z "${BACKUP_DATA:=}" ]] || [[ ! -d "${BACKUP_DATA:=}" ]]; then err "BACKUP_DATA missing" && exit 102; fi
if [[ -z "${GPG_PASSPHRASE:=}" ]]; then err "GPG_PASSPHRASE missing" && exit 104; fi

working_dir=$(mktemp -d)
if [ ! -e "$working_dir" ]; then err "Failed to create temp directory"; exit 1; fi

# backup sqlite
out "Creating sqlite3 backup file"
sqlite3 "file:${VAULTWARDEN_DATA}/${DB_FILE}?mode=ro" ".backup '${working_dir}/${DB_FILE}'";

# copy other files
out "Copying vaultwarden files"
for f in attachments config.json rsa_key.der rsa_key.pem rsa_key.pub.der rsa_key.pub.pem sends; do
    if [[ -e "${VAULTWARDEN_DATA}/$f" ]]; then
      cp -a "${VAULTWARDEN_DATA}/$f" "${working_dir}/$f"
    fi
done

# tar and compress
out "Creating archive"
tar cJfv "${backup_filename}" -C "${working_dir}" .

# encrypt
if [[ -n ${GPG_PASSPHRASE} ]]; then
    printf '%s' "${GPG_PASSPHRASE}" |
    gpg -c --cipher-algo "${GPG_ALGORITHM}" --batch --passphrase-fd 0 "${backup_filename}"  
fi

# remove unencrypted tar
out "Removing unencrypted archive"
rm -f "${backup_filename}"

# sync to remote
if [[ -z "${RCLONE_ARGS:=}" ]] || [[ -z "${RCLONE_REMOTE:=}" ]]; then 
  out "Backing up to local filesystem only (RCLONE_ARGS or RCLONE_REMOTE not set)"
else
  out "Sync to remote"
  rclone --no-check-dest ${RCLONE_ARGS} copy "${backup_filename}.gpg" "${RCLONE_REMOTE}"
fi

# tidy up local files
if [[ -z "${LOCAL_BACKUP_PRUNE_DAYS:=}" ]]; then
  out "Not pruning local backups (LOCAL_BACKUP_PRUNE_DAYS not set)"
else
  find "${BACKUP_DATA}" -name "${BACKUP_BASENAME}*.tar.*" -mtime +"${LOCAL_BACKUP_PRUNE_DAYS}" -delete
fi

# tidy up remote files
if [[ -z "${REMOTE_BACKUP_PRUNE_DAYS:=}" ]]; then
  out "Not pruning remote backups (REMOTE_BACKUP_PRUNE_DAYS not set)"
else
  rclone -vv ${RCLONE_ARGS} --min-age "${REMOTE_BACKUP_PRUNE_DAYS}"d delete "${RCLONE_REMOTE}"
fi

# Make sure the temp directory gets removed on script exit.
trap "exit 1"                 HUP INT PIPE QUIT TERM
trap 'rm -rf "$working_dir"'  EXIT
