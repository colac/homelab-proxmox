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
  storage:
    layout:
      name: direct

    config:
      - type: disk
        id: disk0
        match:
          largest: true
        ptable: gpt
        wipe: superblock
        grub_device: true

      - type: partition
        id: bios-part
        device: disk0
        size: "1M"
        flags: [ bios_grub ]

      - type: partition
        id: efi-part
        device: disk0
        size: "512M"
        flags: [ boot ]

      - type: format
        id: efi-fs
        volume: efi-part
        fstype: vfat
        label: EFI

      - type: mount
        device: efi-fs
        path: /boot/efi

      - type: partition
        id: boot-part
        device: disk0
        size: "1G"

      - type: format
        id: boot-fs
        volume: boot-part
        fstype: ext4

      - type: mount
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

      - type: lvm_lv
        id: lv-root
        name: root
        volgroup: vg0
        size: "25G"

      - type: format
        id: fs-root
        volume: lv-root
        fstype: ext4

      - type: mount
        device: fs-root
        path: /

      - type: lvm_lv
        id: lv-home
        name: home
        volgroup: vg0
        size: "5G"

      - type: format
        id: fs-home
        volume: lv-home
        fstype: ext4

      - type: mount
        device: fs-home
        path: /home
        options: nodev,nosuid

      - type: lvm_lv
        id: lv-tmp
        name: tmp
        volgroup: vg0
        size: "5G"

      - type: format
        id: fs-tmp
        volume: lv-tmp
        fstype: ext4

      - type: mount
        device: fs-tmp
        path: /tmp
        options: nodev,nosuid

      - type: lvm_lv
        id: lv-opt
        name: opt
        volgroup: vg0
        size: -1

      - type: format
        id: fs-opt
        volume: lv-opt
        fstype: ext4

      - type: mount
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
    ntp:
      enabled: true
      ntp_client: systemd-timesyncd
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
