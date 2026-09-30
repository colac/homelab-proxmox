#!/bin/bash
set -euo pipefail

# Elastic Agent installation.
#
# Installs the .deb and deliberately leaves the service DISABLED and stopped.
# An agent baked into a template has no Fleet enrollment and nothing to talk
# to; if it started on boot, every clone would spend its first minutes
# retrying against a Fleet Server that does not exist and filling the journal
# with connection errors. Ansible's `elastic_agent` role enrolls it and starts
# it once there is a Fleet Server to enroll against.
#
# The role also checks this version against stack_version and reinstalls if
# they have drifted, so a stack upgrade rolled out by playbook does not need a
# template rebuild. That same code path installs the agent from scratch if this
# script was skipped, which is what makes INSTALL_ELASTIC_AGENT=false safe.
#
# Env vars:
#   ELASTIC_AGENT_VERSION   version to install (default below)
#   INSTALL_ELASTIC_AGENT   set false to skip entirely

AGENT_VERSION="${ELASTIC_AGENT_VERSION:-9.5.4}"
INSTALL="${INSTALL_ELASTIC_AGENT:-true}"

readonly LOG_FILE="/var/log/elastic-agent-install.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" | tee -a "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    exit 1
}

main() {
    if [[ "${INSTALL}" != "true" ]]; then
        log INFO "INSTALL_ELASTIC_AGENT is '${INSTALL}' — skipping."
        return 0
    fi

    [[ $EUID -eq 0 ]] || error_exit "This script must be run as root or with sudo"

    log INFO "Installing Elastic Agent ${AGENT_VERSION}"

    apt-get update >>"$LOG_FILE" 2>&1 || error_exit "apt-get update failed"
    apt-get install -y curl >>"$LOG_FILE" 2>&1 || error_exit "Failed to install curl"

    local arch deb url path
    arch="$(dpkg --print-architecture)"
    deb="elastic-agent-${AGENT_VERSION}-${arch}.deb"
    url="https://artifacts.elastic.co/downloads/beats/elastic-agent/${deb}"
    path="/tmp/${deb}"

    log INFO "Downloading ${url}"
    curl -fsSL "${url}" -o "${path}" >>"$LOG_FILE" 2>&1 \
        || error_exit "Failed to download ${url}"

    [[ -s "${path}" ]] || error_exit "Downloaded package is empty"

    log INFO "Installing ${deb}"
    if ! dpkg -i "${path}" >>"$LOG_FILE" 2>&1; then
        log WARN "dpkg reported an issue; fixing dependencies"
        apt-get install -f -y >>"$LOG_FILE" 2>&1 \
            || error_exit "Failed to install Elastic Agent"
    fi

    rm -f "${path}"

    # The whole point: installed but inert until Ansible enrolls it.
    log INFO "Disabling the service until Ansible enrolls this host with Fleet"
    systemctl stop elastic-agent >>"$LOG_FILE" 2>&1 || true
    systemctl disable elastic-agent >>"$LOG_FILE" 2>&1 || true

    command -v elastic-agent >/dev/null 2>&1 \
        || error_exit "Elastic Agent installation verification failed"

    log SUCCESS "Elastic Agent $(elastic-agent version 2>/dev/null | head -n1) installed, service disabled"
}

main "$@"
