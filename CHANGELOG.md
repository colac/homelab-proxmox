## [2.2.2](https://github.com/colac/homelab-proxmox/compare/v2.2.1...v2.2.2) (2026-10-23)


### Bug Fixes

* **ansible:** don't count apt's phased or kept-back packages as pending ([a1b0311](https://github.com/colac/homelab-proxmox/commit/a1b0311a49e51febaddecc5c186df5430bc94c0e))
* **ansible:** keep the update plan and guest list when --limit is used ([8158bb9](https://github.com/colac/homelab-proxmox/commit/8158bb90cf1bc498784d2f12c89ebaaae87c1ae6))
* **packer:** write unattended-upgrades' origins as real placeholders ([f8c2bae](https://github.com/colac/homelab-proxmox/commit/f8c2baee0c411098ad0d4b43a7b05e02fe379be2))

## [2.2.1](https://github.com/colac/homelab-proxmox/compare/v2.2.0...v2.2.1) (2026-10-23)


### Bug Fixes

* **ansible:** never sudo on the controller in the update playbook ([fddaab7](https://github.com/colac/homelab-proxmox/commit/fddaab725a60fdc040d58bf2b2080568f3fd7589))

# [2.2.0](https://github.com/colac/homelab-proxmox/compare/v2.1.0...v2.2.0) (2026-10-23)


### Bug Fixes

* **scripts:** report a disk with smart disabled as unknown, not failed ([149dffa](https://github.com/colac/homelab-proxmox/commit/149dffa3a6d6f87c1062f3f265e2d34075310182))


### Features

* **ansible:** add the update procedure every repo runs for its machines ([f6101bc](https://github.com/colac/homelab-proxmox/commit/f6101bc6d31f471b4d8acc577e3ce9f9d410a332))
* **dns:** give the pi-hole container 1 gb and list it as an agent target ([3262cfb](https://github.com/colac/homelab-proxmox/commit/3262cfb883cb4669208a3720bc21df58c70afb4a))
* **proxmox:** script the node's api identities, media and config backup ([a90b728](https://github.com/colac/homelab-proxmox/commit/a90b72827aa3b525582464408e9eedb10d4ce25b))
* **truenas:** declare users, shares and the usb backup in ansible ([b700695](https://github.com/colac/homelab-proxmox/commit/b70069551b4f0e6d2b68a999cba11552e66462b3))

# [2.1.0](https://github.com/colac/homelab-proxmox/compare/v2.0.1...v2.1.0) (2026-10-07)


### Bug Fixes

* **packer:** point new templates at the Pi-hole at 192.168.1.153 ([a764071](https://github.com/colac/homelab-proxmox/commit/a76407186f1378d28d802d508bc563013ff8b514))


### Features

* **dns:** run the LAN's Pi-hole as code in core ([9c90aee](https://github.com/colac/homelab-proxmox/commit/9c90aee76605931f634e047570de9357a128880f))

## [2.0.1](https://github.com/colac/homelab-proxmox/compare/v2.0.0...v2.0.1) (2026-10-07)


### Bug Fixes

* **base-vm:** declare Proxmox's unset startup_shutdown values ([95af56d](https://github.com/colac/homelab-proxmox/commit/95af56d3bbdc8c882b63c4b7980304a3b55192c5))
* **base-vm:** move cores and sockets into the cpu block ([a3afce7](https://github.com/colac/homelab-proxmox/commit/a3afce78f4f45faf367d20990b0d33c3b5bb71a0))

# [2.0.0](https://github.com/colac/homelab-proxmox/compare/v1.3.1...v2.0.0) (2026-10-06)


### Code Refactoring

* split monitoring and workloads into their own repos ([aa07fd6](https://github.com/colac/homelab-proxmox/commit/aa07fd6144f82c33759b9562cfb66e93ec445647))


### BREAKING CHANGES

* the Elastic stack moved to homelab-proxmox-monitoring
and Nextcloud/k3s to homelab-proxmox-workloads. Consumers use base-vm
via git::...//terraform/modules/base-vm?ref=vX.Y.Z and colac.homelab
via ansible/requirements.yml at the same tag.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

## [1.3.1](https://github.com/colac/homelab-proxmox/compare/v1.3.0...v1.3.1) (2026-09-30)


### Bug Fixes

* **docker_data:** keep containerd images on the data disk ([b7a2742](https://github.com/colac/homelab-proxmox/commit/b7a2742d96a8f8c0db5ee4d0975631d564e1beeb))

# [1.3.0](https://github.com/colac/homelab-proxmox/compare/v1.2.0...v1.3.0) (2026-09-25)


### Features

* single-VM Elastic monitoring stack, SOPS secrets, Ubuntu 26.04 template ([d60dfa9](https://github.com/colac/homelab-proxmox/commit/d60dfa9e340e6a3dbca0f652da2c17f8d8917df9))

# [1.2.0](https://github.com/colac/homelab-proxmox/compare/v1.1.0...v1.2.0) (2026-08-02)


### Features

* deployed nextcloud+TrueNAS(manual) ([e4cc9d7](https://github.com/colac/homelab-proxmox/commit/e4cc9d7ae4e4ad614efafc9f0f585745bbef1bdc))

# [1.1.0](https://github.com/colac/homelab-proxmox/compare/v1.0.0...v1.1.0) (2025-12-08)


### Features

* convert tf to module & docs ([9aaa752](https://github.com/colac/homelab-proxmox/commit/9aaa752200417eab0e0eba4a7d0f4f32cbf12cd0))

# 1.0.0 (2025-12-02)


### Features

* packer+terraform working ([83ce14d](https://github.com/colac/homelab-proxmox/commit/83ce14dfc7e062e05885951aeae762edccf11947))
