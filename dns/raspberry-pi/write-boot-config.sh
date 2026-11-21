#!/usr/bin/env bash
# Write pihole-pi's first-boot files onto a freshly flashed Raspberry Pi OS
# boot partition. Flash first, with Raspberry Pi Imager and NO OS
# customisation, then mount the partition (unplug and replug the drive).
#
#   dns/raspberry-pi/write-boot-config.sh <mounted bootfs> <user name>
#
# Prompts for the console password and stores only its SHA-512 hash, on the
# boot partition. cloud-init reads the files on first boot only.
set -euo pipefail

usage() { echo "usage: $0 <mounted bootfs> <user name>" >&2; exit 2; }
[ $# -eq 2 ] || usage
boot=$1 user=$2
here=$(cd "$(dirname "$0")" && pwd)
key_file=${PI_SSH_KEY_FILE:-$HOME/.ssh/homelab-proxmox.pub}

# The target must be a Raspberry Pi OS boot partition that reads cloud-init.
[ -f "$boot/cmdline.txt" ] || { echo "$boot has no cmdline.txt: not a Raspberry Pi boot partition" >&2; exit 1; }
[ -f "$boot/meta-data" ] || {
  echo "$boot has no meta-data: this image predates cloud-init (needs Raspberry Pi OS 13, November 2025 or later)" >&2
  exit 1
}
[ -f "$key_file" ] || { echo "public key $key_file not found (set PI_SSH_KEY_FILE)" >&2; exit 1; }
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "invalid user name: $user" >&2; exit 1; }

# Leftovers from an Imager customisation would run alongside cloud-init.
for f in firstrun.sh userconf.txt custom.toml; do
  [ -e "$boot/$f" ] && echo "warning: $boot/$f exists (an Imager customisation); remove it or re-flash without customisation" >&2
done
grep -q 'firstrun.sh' "$boot/cmdline.txt" && echo "warning: cmdline.txt calls firstrun.sh; re-flash without customisation" >&2

# A ready hash may come from the environment (e.g. later from secrets.yaml
# through sops-exec); otherwise ask for the password.
if [ -z "${PI_PASSWORD_HASH:-}" ]; then
  echo "Console password for $user (typed twice, never stored in clear):"
  PI_PASSWORD_HASH=$(openssl passwd -6)
fi
[[ $PI_PASSWORD_HASH == '$6$'* ]] || { echo "PI_PASSWORD_HASH is not a SHA-512 crypt hash" >&2; exit 1; }
PI_SSH_KEY=$(head -n1 "$key_file")
PI_USER=$user
export PI_USER PI_PASSWORD_HASH PI_SSH_KEY

# Only these three names are substituted, so a '$' in the hash stays intact.
# shellcheck disable=SC2016
envsubst '${PI_USER} ${PI_PASSWORD_HASH} ${PI_SSH_KEY}' \
  < "$here/user-data.tmpl" > "$boot/user-data"
cp "$here/network-config" "$boot/network-config"
sync -f "$boot/user-data"   # flush this partition only

echo "Written: $boot/user-data, $boot/network-config (meta-data left as shipped)."
echo "Check:   grep -E '^(hostname|  - name)' '$boot/user-data'"
echo "Then unmount, boot the Pi on Ethernet and wait 2-3 minutes:"
echo "         ssh -i ${key_file%.pub} $user@192.168.1.53"
