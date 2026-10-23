#!/bin/bash
# Configure the Proxmox VE host with everything the homelab repos depend on.
#
# Idempotent: run it on a fresh install to rebuild, or on the live host to
# put drift back. It only adds or corrects what is declared below; it never
# deletes users, roles, tokens or files it does not know about.
#
# What it does NOT do — the installer and the backup (backup.sh) own these:
# network (/etc/network/interfaces), storage, hostname, and every VM/CT config.
#
# Run on the node as root, --check first (changes nothing, prints the plan):
#   scp -r proxmox root@192.168.1.169:/root/homelab-proxmox-host
#   ssh root@192.168.1.169 /root/homelab-proxmox-host/configure.sh --check
#   ssh root@192.168.1.169 /root/homelab-proxmox-host/configure.sh
#
# API tokens: a token's secret is shown exactly once, when it is created. This
# script creates missing tokens and prints their secrets; it never regenerates
# an existing one. Store each secret where docs/CREDENTIALS.md says.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE="$(hostname)"
CHECK=0
[[ ${1:-} == --check ]] && CHECK=1

# ---------------------------------------------------------------------------
# Declared state — taken from the live node on 2026-10-08 (`pveum role list`,
# `pveum acl list`). Each entry mirrors docs/CREDENTIALS.md: change both.
# ---------------------------------------------------------------------------

# role|privileges
ROLES=(
    "PackerProv|Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Modify VM.Allocate VM.Audit VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Console VM.GuestAgent.Audit VM.PowerMgmt"
    "TerraformRole|Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit SDN.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.GuestAgent.Audit VM.Migrate VM.PowerMgmt"
    "McpReadOnlyRole|Datastore.Audit Pool.Audit Sys.Audit VM.Audit"
)

# user|role|acl path|comment — the comment is only set when the user is
# created. Users get no password: they authenticate with their API token.
USERS=(
    "packer@pve|PackerProv|/|Packer template builds (homelab-proxmox core)"
    "terraform@pve|TerraformRole|/|Terraform: monitoring and workloads repos"
    "terraform-core@pve|TerraformRole|/|Terraform: core dns/ (Pi-hole container)"
    "mcp@pve|McpReadOnlyRole|/|Read-only MCP access"
)

# user|token id — privsep 0: the token carries its user's permissions.
TOKENS=(
    "packer@pve|packer-automation"
    "terraform@pve|terraform-automation"
    "terraform-core@pve|terraform-automation-core"
    "mcp@pve|mcp"
)

# Optional read-only identity for prometheus-pve-exporter (monitoring repo).
# Off: the plan is for Proxmox to push metrics itself (OpenTelemetry below).
ENABLE_PVE_EXPORTER="${ENABLE_PVE_EXPORTER:-0}"

# Files on the node's `local` storage that Packer and Terraform reference by
# name. filename|content|url|sha256 — checksums from each release's SHA256SUMS.
DOWNLOADS=(
    "ubuntu-24.04.3-live-server-amd64.iso|iso|https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso|c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
    "ubuntu-26.04.1-live-server-amd64.iso|iso|https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-live-server-amd64.iso|cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927"
)
# LXC templates come from Proxmox's own index (pveam verifies them).
LXC_TEMPLATES=(
    "debian-13-standard_13.6-1_amd64.tar.zst"
)

# Metric server: Proxmox pushes node, guest and storage metrics as OTLP/HTTP.
# Off until the monitoring VM runs an OTLP receiver that listens on the LAN —
# pushing to nothing only fills the journal with send errors.
#   OTEL_SERVER=192.168.1.87 OTEL_BEARER_TOKEN=… ./configure.sh
OTEL_ID="elastic"
OTEL_SERVER="${OTEL_SERVER:-}"
OTEL_PORT="${OTEL_PORT:-4318}"
OTEL_PROTOCOL="${OTEL_PROTOCOL:-http}"
OTEL_BEARER_TOKEN="${OTEL_BEARER_TOKEN:-}"

# ---------------------------------------------------------------------------

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Every change goes through run: --check prints it instead.
run() {
    if [[ $CHECK == 1 ]]; then
        printf '    would run: %s\n' "$*"
    else
        "$@"
    fi
}

[[ $EUID -eq 0 ]] || die "run as root on the Proxmox node"
command -v pveum >/dev/null || die "pveum not found — is this a Proxmox VE node?"
[[ $CHECK == 1 ]] && log "check mode: nothing will be changed"

exists() { pvesh get "$1" >/dev/null 2>&1; }

# Perl, not Python: Proxmox VE is written in Perl, so JSON::PP is always there.
sorted_words() { perl -e 'print join(" ", sort split(" ", $ARGV[0]))' "$1"; }

role_privs() {
    pvesh get "/access/roles/$1" --output-format json |
        perl -MJSON::PP -0777 -ne 'my $h = decode_json($_); print join(" ", sort grep { $h->{$_} } keys %$h)'
}

# Arguments go in through the environment: with -n, perl would read @ARGV
# as input files.
has_acl() {
    pvesh get /access/acl --output-format json |
        ACL_PATH="$1" ACL_UGID="$2" ACL_ROLE="$3" perl -MJSON::PP -0777 -ne '
            exit((grep { $_->{path} eq $ENV{ACL_PATH} && $_->{ugid} eq $ENV{ACL_UGID}
                         && $_->{roleid} eq $ENV{ACL_ROLE} } @{decode_json($_)}) ? 0 : 1)
        '
}

user_tokens() {
    pvesh get "/access/users/$1/token" --output-format json |
        perl -MJSON::PP -0777 -ne 'print join(" ", map { $_->{tokenid} } @{decode_json($_)})'
}

configure_roles() {
    local entry role privs want have
    for entry in "${ROLES[@]}"; do
        IFS='|' read -r role privs <<<"$entry"
        want="$(sorted_words "$privs")"
        if ! exists "/access/roles/$role"; then
            log "role $role: missing — creating"
            run pveum role add "$role" --privs "$want"
            continue
        fi
        have="$(role_privs "$role")"
        if [[ $have == "$want" ]]; then
            log "role $role: in sync"
        else
            log "role $role: drifted — setting the declared privileges"
            printf '    live:     %s\n    declared: %s\n' "$have" "$want"
            # Without --append, modify replaces the whole list.
            run pveum role modify "$role" --privs "$want"
        fi
    done
}

ensure_user() {
    local user="$1" role="$2" path="$3" comment="$4"
    if exists "/access/users/$user"; then
        log "user $user: exists"
    else
        log "user $user: missing — creating"
        run pveum user add "$user" --comment "$comment"
    fi
    if has_acl "$path" "$user" "$role"; then
        log "user $user: $role on $path"
    else
        log "user $user: granting $role on $path"
        run pveum acl modify "$path" --users "$user" --roles "$role"
    fi
}

ensure_token() {
    local user="$1" token="$2" existing=""
    exists "/access/users/$user" && existing="$(user_tokens "$user")"
    if [[ " $existing " == *" $token "* ]]; then
        log "token $user!$token: exists (secret unchanged)"
    else
        log "token $user!$token: missing — creating${existing:+ (tokens on this user: $existing)}"
        [[ $CHECK == 1 ]] || log "copy the secret below NOW, it is not shown again"
        run pveum user token add "$user" "$token" --privsep 0
    fi
}

configure_access() {
    local entry user role path comment token
    if [[ $ENABLE_PVE_EXPORTER == 1 ]]; then
        USERS+=("pve-exporter@pve|PVEAuditor|/|Read-only Prometheus exporter (monitoring)")
        TOKENS+=("pve-exporter@pve|monitoring")
    fi
    for entry in "${USERS[@]}"; do
        IFS='|' read -r user role path comment <<<"$entry"
        ensure_user "$user" "$role" "$path" "$comment"
    done
    for entry in "${TOKENS[@]}"; do
        IFS='|' read -r user token <<<"$entry"
        ensure_token "$user" "$token"
    done
}

configure_downloads() {
    local entry file content url sum
    for entry in "${DOWNLOADS[@]}"; do
        IFS='|' read -r file content url sum <<<"$entry"
        if [[ -f "/var/lib/vz/template/$content/$file" ]]; then
            log "local:$content/$file: present"
            continue
        fi
        log "local:$content/$file: missing — downloading"
        run pvesh create "/nodes/$NODE/storage/local/download-url" \
            --content "$content" --filename "$file" --url "$url" \
            --checksum "$sum" --checksum-algorithm sha256
    done

    local tmpl
    for tmpl in "${LXC_TEMPLATES[@]}"; do
        if [[ -f "/var/lib/vz/template/cache/$tmpl" ]]; then
            log "local:vztmpl/$tmpl: present"
            continue
        fi
        log "local:vztmpl/$tmpl: missing — downloading"
        run pveam update
        run pveam download local "$tmpl" ||
            die "$tmpl is no longer in Proxmox's index (pveam available --section system); update it here and in dns/terraform/variables.tf"
    done
}

configure_metrics() {
    if [[ -z $OTEL_SERVER ]]; then
        log "metric server: skipped (set OTEL_SERVER once the OTLP receiver exists)"
        return
    fi
    local args=(--server "$OTEL_SERVER" --port "$OTEL_PORT"
        --otel-protocol "$OTEL_PROTOCOL" --otel-path /v1/metrics)
    # Proxmox takes extra headers as base64-encoded JSON (otel-headers).
    if [[ -n $OTEL_BEARER_TOKEN && $CHECK == 1 ]]; then
        args+=(--otel-headers '<Authorization: Bearer …, redacted>')
    elif [[ -n $OTEL_BEARER_TOKEN ]]; then
        args+=(--otel-headers "$(printf '{"Authorization":"Bearer %s"}' "$OTEL_BEARER_TOKEN" | base64 -w0)")
    fi
    if exists "/cluster/metrics/server/$OTEL_ID"; then
        log "metric server $OTEL_ID: updating"
        run pvesh set "/cluster/metrics/server/$OTEL_ID" "${args[@]}"
    else
        log "metric server $OTEL_ID: creating"
        run pvesh create "/cluster/metrics/server/$OTEL_ID" --type opentelemetry "${args[@]}"
    fi
}

configure_backup() {
    command -v age >/dev/null || { log "age: missing — installing"; run apt-get install -y age; }
    log "backup: installing pve-config-backup and its daily timer"
    run install -m 0755 "$SCRIPT_DIR/backup.sh" /usr/local/sbin/pve-config-backup
    run install -m 0644 "$SCRIPT_DIR/systemd/pve-config-backup.service" \
        "$SCRIPT_DIR/systemd/pve-config-backup.timer" /etc/systemd/system/
    # Settings survive re-runs: only seeded when absent.
    [[ -f /etc/default/pve-config-backup ]] ||
        run install -m 0644 "$SCRIPT_DIR/pve-config-backup.default" /etc/default/pve-config-backup
    run systemctl daemon-reload
    run systemctl enable --now pve-config-backup.timer
}

configure_roles
configure_access
configure_downloads
configure_metrics
configure_backup
log "done"
