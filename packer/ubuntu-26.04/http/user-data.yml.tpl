#cloud-config
autoinstall:
  version: 1

  # User Identity
  identity:
    hostname: ${hostname}
    username: ${username}
    password: '${password_hash}'

  # Network
  network:
    version: 2
    ethernets:
      ens18:
        dhcp4: true
        nameservers:
          addresses:
%{ for ns in nameservers ~}
            - ${ns}
%{ endfor ~}

  # Storage
  #
  # There is deliberately NO `layout:` key here. Subiquity's autoinstall
  # reference is explicit: "If the layout feature is used to configure the
  # disks, the config section is not used." A `layout: {name: direct}` sitting
  # above this block — as in packer/ubuntu-24.04 — silently discards every
  # action below and installs a single plain root partition with no LVM at
  # all. Adding `layout:` back disables everything you see here.
  #
  # Only the OS disk is described. The Docker data disk is attached by
  # Terraform and initialised by the Ansible `docker_data` role, so that each
  # VM's docker-vg is created with its own LVM UUIDs. Partitioning it here
  # instead would give every clone a byte-identical PV/VG, and moving one VM's
  # data disk to another would need `vgimportclone` before LVM would touch it.
  storage:
    config:
      - type: disk
        id: disk0
        match:
          size: largest
        ptable: gpt
        wipe: superblock
        grub_device: true

      - type: partition
        id: bios-part
        device: disk0
        size: 1M
        flag: bios_grub

      - type: partition
        id: efi-part
        device: disk0
        size: 512M
        flag: boot

      - type: format
        id: efi-fs
        volume: efi-part
        fstype: fat32
        label: EFI

      - type: mount
        id: mount-efi
        device: efi-fs
        path: /boot/efi

      - type: partition
        id: boot-part
        device: disk0
        size: 1G

      - type: format
        id: boot-fs
        volume: boot-part
        fstype: ext4

      - type: mount
        id: mount-boot
        device: boot-fs
        path: /boot

      - type: partition
        id: lvm-part
        device: disk0
        size: -1

      - type: lvm_volgroup
        id: vg0
        name: ubuntu-vg
        devices: [ lvm-part ]

      # NOTE: the action type is `lvm_partition`, not `lvm_lv`. subiquity
      # registers the LVM_LogicalVolume class as @fsobj("lvm_partition"), and
      # an unrecognised type is *silently ignored* — it never reaches byid, so
      # the `format` action that references it then fails its byid lookup, the
      # KeyError is swallowed, and the install dies further down with the
      # baffling "Filesystem.__init__() missing 1 required keyword-only
      # argument: 'volume'". The name is wrong-looking but correct.
      #
      # Every logical volume below is given an explicit size rather than
      # consuming the rest of the group. That is the point of using LVM here:
      # what is left over stays as free extents in ubuntu-vg, so whichever
      # filesystem fills up first can be grown in place with
      # `lvextend -L +<n>G /dev/ubuntu-vg/<lv> && resize2fs /dev/ubuntu-vg/<lv>`
      # with no repartitioning and no reboot. An LV sized `-1` would swallow
      # the remainder and take that option away.
      - type: lvm_partition
        id: lv-root
        name: root
        volgroup: vg0
        size: "${lv_root_size}"

      - type: format
        id: fs-root
        volume: lv-root
        fstype: ext4

      - type: mount
        id: mount-root
        device: fs-root
        path: /

      - type: lvm_partition
        id: lv-home
        name: home
        volgroup: vg0
        size: "${lv_home_size}"

      - type: format
        id: fs-home
        volume: lv-home
        fstype: ext4

      - type: mount
        id: mount-home
        device: fs-home
        path: /home
        options: nodev,nosuid

      - type: lvm_partition
        id: lv-tmp
        name: tmp
        volgroup: vg0
        size: "${lv_tmp_size}"

      - type: format
        id: fs-tmp
        volume: lv-tmp
        fstype: ext4

      - type: mount
        id: mount-tmp
        device: fs-tmp
        path: /tmp
        options: nodev,nosuid

      # /opt holds the compose projects (elastic_base_dir). Only the compose
      # files, .env, certs and secrets live here — a few MB. The container
      # data itself (Elasticsearch's `esdata` volume, Nextcloud AIO's
      # mastercontainer volume) is under /var/lib/docker, which is the
      # separate data disk.
      - type: lvm_partition
        id: lv-opt
        name: opt
        volgroup: vg0
        size: "${lv_opt_size}"

      - type: format
        id: fs-opt
        volume: lv-opt
        fstype: ext4

      - type: mount
        id: mount-opt
        device: fs-opt
        path: /opt
        options: noatime,nodiratime

%{ if enable_proxy ~}
  proxy: ${proxy_url}
%{ endif ~}

  # SSH Configuration
  ssh:
    install-server: yes
    allow-pw: false
%{ if length(ssh_authorized_keys) > 0 ~}
    authorized-keys:
%{ for key in ssh_authorized_keys ~}
      - ${key}
%{ endfor ~}
%{ endif ~}

  # Packages
  packages:
%{ for package in packages ~}
    - ${package}
%{ endfor ~}

  # Late commands
  late-commands:
    # Fix the initrd network race (see scripts/15-fix-initrd-network.sh for
    # the full story): dracut's hostonly mode bundles network modules into
    # the initrd based on the BUILD machine, not the target, so on first
    # boot systemd-networkd DHCPs the NIC before cloud-init's netplan
    # rename gets a chance to run, and the rename fails ("[busy] Error
    # renaming ... from ens18 to eth0") — which is why this has to run here,
    # chrooted into /target during install, and NOT as a Packer provisioner:
    # a provisioner only runs after that first boot has already raced.
    # The script is base64-embedded (see locals.pkr.hcl) purely so its own
    # single-quoted heredocs survive being dropped into this YAML string
    # untouched — decode, execute, remove.
    - curtin in-target --target=/target -- bash -c "echo ${initrd_network_fix_b64} | base64 -d > /tmp/15-fix-initrd-network.sh && chmod +x /tmp/15-fix-initrd-network.sh && /tmp/15-fix-initrd-network.sh && rm -f /tmp/15-fix-initrd-network.sh"

    # Disable IPv6
    - curtin in-target --target=/target -- sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ipv6.disable=1"/' /etc/default/grub
    - curtin in-target --target=/target -- update-grub

    # Fix fstab fsck pass numbers (only root should be 0 1, others should be 0 2)
    - curtin in-target --target=/target -- sed -i 's|\(/home.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/tmp.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/opt.*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/boot .*\) 0 1|\1 0 2|' /etc/fstab
    - curtin in-target --target=/target -- sed -i 's|\(/boot/efi.*\) 0 1|\1 0 2|' /etc/fstab

  # User data configuration
  user-data:
    # Timezone
    timezone: ${timezone}
    # Locale and Keyboard
    locale: ${locale}
    keyboard:
      layout: ${keyboard_layout}
      variant: ${keyboard_variant}
    # packages
    package_update: true
    package_upgrade: true
    manage_etc_hosts: true
    preserve_hostname: false
    # Regenerates SSH host keys
    ssh_deletekeys: true
    ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
    ssh_quiet_keygen: false
    # disable root account
    disable_root: true
    # NTP Configuration
    #
    # chrony, not systemd-timesyncd: cloud-init's ntp module (cc_ntp.py)
    # defines systemd-timesyncd with an empty `packages: []` list — it
    # assumes the /lib/systemd/systemd-timesyncd binary is already present
    # (historically bundled with the core systemd package) and never
    # installs anything for it. On this 26.04 image that binary/unit isn't
    # there ("Unit systemd-timesyncd.service not found", exit code 5),
    # cc_ntp has no fallback, and the whole run's status flips to `error`.
    # chrony's client entry carries `packages: ["chrony"]`, so cc_ntp
    # installs it if missing — self-healing instead of assuming. It's also
    # first in cloud-init's own default client priority order
    # (chrony, systemd-timesyncd, ntp, ntpdate) and the exact override
    # cloud-init's own docs show as the example for Ubuntu.
    ntp:
      enabled: true
      ntp_client: chrony
      servers:
%{ for server in ntp_servers ~}
        - ${server}
%{ endfor ~}
    users:
      - name: ${username}
        groups: [adm, cdrom, dip, plugdev, sudo, docker]
        shell: /bin/bash
        sudo: 'ALL=(ALL) NOPASSWD:ALL'
        passwd: '${password_hash}'
        lock_passwd: false
%{ if length(ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
%{ if length(additional_users) > 0 ~}
      # Additional users
%{ for user in additional_users ~}
      - name: ${user.name}
        groups: ${jsonencode(user.groups)}
        shell: ${user.shell}
        sudo: ${user.sudo}
        lock_passwd: ${user.lock_passwd}
%{ if length(user.ssh_authorized_keys) > 0 ~}
        ssh_authorized_keys:
%{ for key in ssh_authorized_keys ~}
          - ${key}
%{ endfor ~}
%{ endif ~}
%{ endfor ~}
%{ endif ~}

    write_files:
      # sysctl for swap
      - path: /etc/sysctl.d/80-swap-tuning.conf
        content: |
          # Keep swap usage minimal — only under pressure
          vm.swappiness = 10
          # Strongly prefer keeping application memory in RAM
          vm.vfs_cache_pressure = 50
          # Reduce tendency to reclaim small anonymous memory pages
          vm.page-cluster = 0
          # Avoid full inactive page scans (helps on virtualized systems)
          vm.watermark_scale_factor = 100
          # Improve responsiveness under memory load
          vm.dirty_ratio = 10
          vm.dirty_background_ratio = 5
          # Improve I/O behavior (especially on SSD-backed storage)
          vm.dirty_writeback_centisecs = 1500

      # Elasticsearch bootstrap requirement. ES runs a hard bootstrap check on
      # this at startup and refuses to boot if it is too low — the container
      # exits immediately with "max virtual memory areas vm.max_map_count [65530]
      # is too low". It lives here, not in Ansible, so the OS is fully ready the
      # moment a clone boots. Harmless on VMs that never run ES.
      - path: /etc/sysctl.d/81-elasticsearch.conf
        content: |
          vm.max_map_count=${vm_max_map_count}

      # Raise memlock + nofile for the container runtime. ES locks its heap
      # into RAM (bootstrap.memory_lock) so the JVM heap can never be swapped
      # out, which needs an unlimited memlock ceiling on the host.
      - path: /etc/security/limits.d/99-elasticsearch.conf
        content: |
          *  soft  memlock  unlimited
          *  hard  memlock  unlimited
          *  soft  nofile   65536
          *  hard  nofile   65536

      # Hardened SSH configuration
      - path: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          # Authentication
          PermitRootLogin no
          PubkeyAuthentication yes
          PasswordAuthentication no
          PermitEmptyPasswords no
          # Limit authentication attempts
          MaxAuthTries 3
          MaxSessions 2
          # Protocol and encryption
          Protocol 2
          # Ciphers (strong only)
          Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
          # MACs (strong only)
          MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
          # Key exchange algorithms (strong only)
          KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
          # Logging
          LogLevel VERBOSE
          # Network
          AddressFamily inet  # IPv4 only if you disabled IPv6
          # Banner (optional)
          Banner /etc/ssh/banner

      # SSH banner
      - path: /etc/ssh/banner
        content: |
          ***************************************************************************
                              AUTHORIZED ACCESS ONLY
          Unauthorized access to this system is forbidden and will be
          prosecuted by law. By accessing this system, you agree that your
          actions may be monitored if unauthorized usage is suspected.
          ***************************************************************************

      # Automatic security updates
      - path: /etc/apt/apt.conf.d/50unattended-upgrades
        content: |
          Unattended-Upgrade::Allowed-Origins {
              "$$\{distro_id\}:$$\{distro_codename\}";
              "$$\{distro_id\}:$$\{distro_codename\}-security";
              "$$\{distro_id\}ESMApps:$$\{distro_codename\}-apps-security";
              "$$\{distro_id\}ESM:$$\{distro_codename\}-infra-security";
          };
          Unattended-Upgrade::AutoFixInterruptedDpkg "true";
          Unattended-Upgrade::MinimalSteps "true";
          Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
          Unattended-Upgrade::Remove-Unused-Dependencies "true";
          Unattended-Upgrade::Automatic-Reboot "false";
          Unattended-Upgrade::Automatic-Reboot-Time "03:00";
          Unattended-Upgrade::SyslogEnable "true";

      - path: /etc/apt/apt.conf.d/20auto-upgrades
        content: |
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Download-Upgradeable-Packages "1";
          APT::Periodic::AutocleanInterval "7";
          APT::Periodic::Unattended-Upgrade "1";

      # Login banner
      - path: /etc/issue.net
        content: |
          ***************************************************************************
                              AUTHORIZED ACCESS ONLY
          Unauthorized access to this system is forbidden and will be
          prosecuted by law. By accessing this system, you agree that your
          actions may be monitored if unauthorized usage is suspected.
          ***************************************************************************

      # # rkhunter
      # - path: /etc/systemd/system/rkhunter.service
      #   content: |
      #     [Unit]
      #     Description=Run rkhunter scan
      #     [Service]
      #     Type=oneshot
      #     ExecStart=/usr/bin/rkhunter --check --sk | tee /var/log/rkhunter.log

      # - path: /etc/systemd/system/rkhunter.timer
      #   content: |
      #     [Unit]
      #     Description=Daily rkhunter scan
      #     [Timer]
      #     OnCalendar=daily
      #     Persistent=true
      #     [Install]
      #     WantedBy=timers.target

      # # chkrootkit
      # - path: /etc/systemd/system/chkrootkit.service
      #   content: |
      #     [Unit]
      #     Description=Run chkrootkit scan
      #     [Service]
      #     Type=oneshot
      #     ExecStart=/usr/sbin/chkrootkit | tee /var/log/chkrootkit.log

      # - path: /etc/systemd/system/chkrootkit.timer
      #   content: |
      #     [Unit]
      #     Description=Daily chkrootkit scan
      #     [Timer]
      #     OnCalendar=daily
      #     Persistent=true
      #     [Install]
      #     WantedBy=timers.target

      # # lynis
      # - path: /etc/systemd/system/lynis-audit.service
      #   content: |
      #     [Unit]
      #     Description=Lynis Security Audit
      #     [Service]
      #     Type=oneshot
      #     ExecStart=/usr/sbin/lynis audit system --quiet | tee /var/log/lynis/lynis.log

      # - path: /etc/systemd/system/lynis-audit.timer
      #   content: |
      #     [Unit]
      #     Description=Weekly Lynis audit
      #     [Timer]
      #     OnCalendar=weekly
      #     Persistent=true
      #     [Install]
      #     WantedBy=timers.target

      # # AIDE
      # - path: /etc/systemd/system/aide-check.service
      #   content: |
      #     [Unit]
      #     Description=AIDE Integrity Check
      #     [Service]
      #     Type=oneshot
      #     ExecStart=/usr/bin/aide --check | tee /var/log/aide/aide.log

      # - path: /etc/systemd/system/aide-check.timer
      #   content: |
      #     [Unit]
      #     Description=AIDE Daily Check
      #     [Timer]
      #     OnCalendar=daily
      #     Persistent=true
      #     [Install]
      #     WantedBy=timers.target

    runcmd:
      # Disable root login
      - passwd -l root
      - usermod -s /usr/sbin/nologin root

      # Set restrictive permissions on SSH config
      - chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf
      # Restart SSH to apply changes
      #- systemctl restart sshd
      - systemctl enable ssh
      - systemctl start ssh

      # Enable and start services
      - systemctl enable auditd
      - systemctl start auditd

      # Set timezone
      - timedatectl set-timezone UTC

      # Enable NTP
      - timedatectl set-ntp true

      # Enable qemu-guest-agent
      - systemctl enable qemu-guest-agent

      # Compose base directory for the Elastic Stack projects. Created here
      # rather than by Ansible for the same reason as the sysctl above — the
      # OS arrives ready. Must stay in sync with elastic_base_dir in
      # ansible/inventory/group_vars/all.yml.
      - mkdir -p ${elastic_base_dir}
      - chmod 0755 ${elastic_base_dir}

      # # ===== SECURITY TOOLS CONFIGURATION =====

      # # -----------------------------
      # # Configure rkhunter
      # # -----------------------------
      # - sed -i 's/UPDATE_MIRRORS=0/UPDATE_MIRRORS=1/' /etc/rkhunter.conf
      # - sed -i 's/MIRRORS_MODE=1/MIRRORS_MODE=0/' /etc/rkhunter.conf
      # - sed -i 's/USE_LOCKING=0/USE_LOCKING=1/' /etc/rkhunter.conf
      # - rkhunter --update

      # # -----------------------------
      # # Configure lynis
      # # -----------------------------
      # - mkdir -p /var/log/lynis
      # - chmod 700 /var/log/lynis

      # Reload systemd units after installing all custom services
      - systemctl daemon-reload
