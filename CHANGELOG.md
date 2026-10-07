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
