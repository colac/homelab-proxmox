#!/bin/bash
# Back up the Proxmox host's configuration as one age-encrypted archive.
#
# Installed as /usr/local/sbin/pve-config-backup by configure.sh and run daily
# by pve-config-backup.timer; also safe to run by hand. Settings come from
# /etc/default/pve-config-backup.
#
# The archive holds secrets — /etc/pve/priv has the API token secrets, the
# cluster's private keys and the users' password hashes — so it is encrypted
# to the homelab's age public key (the recipient in .sops.yaml) before it
# touches disk. The node never holds a key that can decrypt it.
#
# This is the host's configuration, not the guests' disks: back those up with
# vzdump (Datacenter → Backup).

set -euo pipefail

# shellcheck source=/dev/null
[[ -f /etc/default/pve-config-backup ]] && . /etc/default/pve-config-backup

BACKUP_DIR="${BACKUP_DIR:-/root/pve-config-backups}"
AGE_RECIPIENTS="${AGE_RECIPIENTS:?set AGE_RECIPIENTS in /etc/default/pve-config-backup}"
KEEP_DAYS="${KEEP_DAYS:-30}"

# Everything a rebuilt node needs that is not in the repos. config.db is the
# database behind /etc/pve; Proxmox's documented recovery is to copy it onto a
# fresh install (see README.md). /etc/pve itself is included as readable files.
PATHS=(
    /var/lib/pve-cluster/config.db
    /etc/pve
    /etc/network/interfaces /etc/network/interfaces.d
    /etc/hostname /etc/hosts /etc/resolv.conf /etc/fstab
    /etc/vzdump.conf
    /etc/apt/sources.list /etc/apt/sources.list.d
    /etc/sysctl.d /etc/modprobe.d /etc/modules-load.d /etc/modules
    /etc/default/grub /etc/kernel/cmdline
    /etc/lvm/backup
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d /root/.ssh
    /etc/cron.d /etc/systemd/system
    /etc/default/pve-config-backup
)

die() { printf 'pve-config-backup: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"
command -v age >/dev/null || die "age is not installed (apt-get install age)"
# A share that failed to mount must not silently fill the local disk instead.
if [[ -n ${BACKUP_MOUNT:-} ]]; then
    mountpoint -q "$BACKUP_MOUNT" || die "$BACKUP_MOUNT is not mounted"
fi

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

stamp="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/pve-config-$(hostname)-$stamp.tar.gz.age"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A plain-text inventory of what is running, for orientation after a restore.
{
    echo "# $(hostname) — $(date -Is)"
    pveversion -v
    echo; echo "## guests"
    qm list 2>/dev/null || true
    pct list 2>/dev/null || true
    echo; echo "## storage"
    pvesm status 2>/dev/null || true
} >"$work/manifest.txt"
dpkg --get-selections >"$work/dpkg-selections.txt"

# Only paths that exist on this node; tar would fail on the rest.
present=()
for p in "${PATHS[@]}"; do
    [[ -e $p ]] && present+=("$p")
done

recipients=()
for r in $AGE_RECIPIENTS; do recipients+=(-r "$r"); done

tar -czf - -C "$work" manifest.txt dpkg-selections.txt -C / "${present[@]#/}" |
    age "${recipients[@]}" -o "$out.partial"
mv "$out.partial" "$out"
chmod 0600 "$out"

find "$BACKUP_DIR" -maxdepth 1 -name 'pve-config-*.tar.gz.age' -mtime +"$KEEP_DAYS" -delete

echo "pve-config-backup: wrote $out ($(du -h "$out" | cut -f1))"
