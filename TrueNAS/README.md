# Installing TrueNAS on the TerraMaster F4-425 Plus

Replacing the stock TerraMaster OS (TOS) with **TrueNAS Community Edition** on
the F4-425 Plus. The unit boots TOS from an **internal USB DOM** (a separate
stick inside the case), so installing TrueNAS to the NVMe leaves TOS untouched
and fully reversible.

Hardware is well-matched: Intel N150, 16 GB DDR5, 3× M.2 slots, 4 bays, dual
5GbE, and — unlike older headless TerraMaster units — a **rear HDMI port**, so
the BIOS and installer are visible on a monitor.

## Drive layout

| Device | Role |
|---|---|
| 1× NVMe (M.2) | TrueNAS boot / OS drive |
| 2× WD 8 TB SATA | ZFS **mirror** data pool (8 TB usable, survives one drive failure) |
| Internal USB DOM | Left in place — keeps TOS, otherwise unused |

Two rules behind this:

- **Do not boot TrueNAS from USB or the DOM.** TrueNAS writes logs constantly
  and wears flash out; a real SSD (the NVMe) is the correct boot target. Two M.2
  slots stay free for a future NVMe pool or cache.
- **Two disks means a mirror, not RAIDZ.** RAIDZ1 needs three or more drives. A
  mirror is correct until more disks are added.

> **Burn in the disks first.** Do not build the pool from a drive whose extended
> SMART self-test aborted or failed — a mirror gives no protection if one half
> was already dying. Validate both with `scripts/check-disk-health.sh` and a
> completed `smartctl -t long` before committing them here.

## What you need

- A **USB stick** (8 GB+) for the installer — it gets wiped
- The **NVMe** installed as the OS target (done)
- A **USB keyboard**, an **HDMI monitor/TV**, and an HDMI cable
- The TrueNAS ISO (below)

## 1. Download and write the installer

Download **TrueNAS Community Edition** — the Linux edition, formerly "SCALE".
Not TrueNAS CORE, which is the legacy FreeBSD line.

- <https://www.truenas.com/download-truenas-community-edition/>
- Take the latest **STABLE** release (the 25.04 "Fangtooth" line or newer).
  Avoid nightly/RC builds.

Write it to the USB stick with **balenaEtcher**, or **Rufus in "DD Image" mode**.

> **Do not use Ventoy** — it does not boot the TrueNAS installer correctly.

## 2. Physical prep

Power off and unplug. With the NVMe and both HDDs seated, the machine is ready.
The internal USB DOM can stay plugged in (the reversible path). Only unplug it
from its motherboard header if a maximally clean machine with zero chance of TOS
interfering is wanted — optional.

## 3. Enter the BIOS

Connect HDMI and the keyboard, plug in the installer USB, and power on.

- **`Del`** repeatedly at power-on → full BIOS setup
- **`F12`** → one-time boot menu (to just pick the USB once)

The HDMI "terminal only" caveat in the specs applies to TOS; the BIOS and the
TrueNAS installer output normal video and are fully visible.

## 4. BIOS settings

Labels vary slightly by firmware revision on the F4-42x AMI BIOS:

1. **Disable TOS-first boot** — set **`TOS Boot First`** (under a *Fast* / *Boot*
   section) to **Disabled**. This is what otherwise skips past the USB.
2. **Disable Secure Boot** — **`Security`** → **Secure Boot** → **Disabled**.
3. **Set boot priority** — **`Boot`** → UEFI Hard Disk / USB Drive BBS
   Priorities → **Boot Option #1** → the installer USB.
4. **Save and exit** — **`F4`**, then confirm.

## 5. Install

The installer boots to a text menu:

1. Choose **Install/Upgrade**.
2. Select the destination drive = the **NVMe**. Do **not** pick a WD 8 TB (that
   is the data pool) or the small internal DOM. The NVMe is usually obvious by
   size.
3. Set the **admin/root password**.
4. Let it finish, **remove the USB stick**, and reboot when prompted.

## 6. Fix the boot order (do not skip)

On the reboot, re-enter the BIOS (`Del`, or the `F12` boot menu) and set
**Boot Option #1 = the NVMe** (the TrueNAS OS drive).

Skipping this leaves the internal DOM / TOS installer at higher priority, and the
box boots back into TOS instead of TrueNAS. This is the most common "it didn't
work" cause on this model.

## 7. First boot and web UI

TrueNAS boots to a console on the HDMI screen that **prints its IP and URL**
(e.g. `http://192.168.1.xxx`). Browse there from a laptop and log in as `admin`.

Then in the web UI:

- **Storage → Create Pool** → mirror → select both WD 8 TB drives.
- **Network** → confirm the 5GbE interface; set a static IP or a DHCP
  reservation on the router.
- Later: SMB / NFS shares, apps, etc.

TrueNAS serves its UI on port 80, so a LAN scan finds it again if the machine
later runs headless.

## Post-install: essential settings

Getting TrueNAS running is the easy part; these turn it into a NAS you can
trust with data. Ordered by how much a skipped item hurts. A ZFS mirror only
protects you if you actually **hear** about a failed disk and have a copy when
the whole box is lost — so alerts and backups are not optional extras.

### Tier 1 — do first (a silent disk failure is the classic regret)

1. **System email + alerts.** Without a delivery channel, a degraded pool, a
   failed scrub, or a SMART error is silent until the second mirror disk dies.
   - **System → General → Email** — set From Email and the SMTP server (port
     587 submission / 465 SSL; a provider app-password works).
   - **Top bar → Alerts (bell) → Alert Settings** — the **E-Mail** entry in the
     *Alert Services* table must be **Enabled**; send a test. That table is the
     delivery channel; the *conditions* below it are built in, not created by
     hand. Pool-health / degraded-vdev, scrub finished/failed, and disk/SMART
     alerts live under the **Storage** category; temperature / PSU / fan under
     **Hardware**. Defaults are sensible (pool-not-healthy is CRITICAL,
     delivered immediately) — you mainly just need working email delivery.
2. **SMART monitoring.** On **25.10 (Goldeye) there is no S.M.A.R.T. service to
   enable and no Data Protection SMART Tests UI** — both were removed. SMART
   attribute polling and ZFS failure detection now run automatically and feed
   the disk-health alerts above, so passive monitoring needs no setup. The
   monthly scrub (next item) is the built-in active surface check. For proactive
   full-surface **long self-tests**, add a cron job under **System → Advanced
   Settings → Cron Jobs** (e.g. `smartctl -t long /dev/sda` monthly, one per
   disk) or install the **Scrutiny** app. On 25.04 (Fangtooth) and earlier,
   use the old flow: **System → Services → S.M.A.R.T.** plus **Data Protection →
   S.M.A.R.T. Tests** (SHORT weekly, LONG monthly).
3. **Verify the scrub task.** Auto-created on pool creation (Sunday 00:00);
   confirm under **Data Protection → Scrub Tasks** and shift its time so it does
   not collide with the monthly LONG SMART test.

### Tier 2 — protect the data

1. **Periodic Snapshot Tasks** on `hdd-home-1/media` (and `documents`) — the
   first defence against accidental deletion and ransomware, which a mirror does
   nothing for. E.g. daily kept two weeks, plus weekly kept two months.
2. **SMB "Previous Versions."** Confirm **Enable Shadow Copies** on the `media`
   share so Windows clients can restore files straight from snapshots.
3. **A real off-box backup (3-2-1).** The mirror is **not** a backup — both
   disks share one box, one PSU, and one `rm -rf`. Use **Data Protection →
   Cloud Sync Tasks** (Backblaze B2 / S3 / Storj) for the irreplaceable data, or
   replicate to a second machine.

### Tier 3 — security

1. **HTTPS for the web UI.** **System → General → GUI** — set a GUI SSL
   Certificate (the built-in self-signed one at minimum) and tick redirect
   HTTP→HTTPS. The install serves plain HTTP.
2. **Two-factor auth.** **Credentials → 2FA** — enable and scan with an
   authenticator app. Keep root SSH login disabled (the default).

### Tier 4 — housekeeping

- **Timezone + NTP** — **System → General**; a wrong clock skews every snapshot
  and scrub schedule and your logs.
- **Static IP / DHCP reservation** for the box so its address never moves — the
  Nextcloud role hard-points at it (see below).
- **UPS** — **System → Services → UPS** if one is attached, for a clean shutdown
  on power loss.
- **Save the config** — **System → General → Manage Configuration → Download
  File**, now and after major changes, so a dead boot NVMe is a quick rebuild.

If you do only three things: **email alerts**, the **monthly scrub** (auto-
created — just confirm it), and a **backup plan** — the mirror and scrub only
help if you hear about a failure and have a copy when the whole box is gone.

## Model-specific notes

- **N150 transcoding:** Intel QuickSync with AV1 / H.265 hardware decode makes
  this modest CPU strong for Jellyfin / Plex. Heavy multi-stream *CPU*
  transcoding is not its strength.
- **16 GB RAM is ample** for a home NAS plus a few apps — no upgrade needed to
  start.
- **Reverting to TOS** is only a boot-order change back to the DOM; installing
  TrueNAS to the NVMe destroys nothing.

## Nextcloud external storage

This TerraMaster is the storage backend for the Nextcloud deployment, replacing
the Synology NAS it previously mounted over SMB.

| Setting | Value |
|---|---|
| `nextcloud_aio_nas_host` | `192.168.1.214` |
| SMB share | `media` → `/mnt/hdd-home-1/media` |
| Subfolders attached | one per user (`hugo`, …) private read-write, `Familia` read-only for every Nextcloud account |
| SMB user | dedicated account, credentials in `ansible/vault.yml` |

`Familia` is deliberately read-only in Nextcloud. Curating it — moving files
from `media/hugo` into `media/Familia` — is done **here**, over SMB or the
TrueNAS shell, where it is an instant rename inside one dataset instead of a
byte-for-byte copy through the Nextcloud VM. Afterwards, re-index with
`occ files:scan --all` on the VM.

Shared mounts are declared in `nextcloud_aio_nas_mounts` in
`ansible/group_vars/nextcloud.yml`; private per-user folders come from the
`nextcloud_aio_users` list in the vault. Both are created by the
`nextcloud_aio` role — see [../ansible/README.md](../ansible/README.md) for the
syntax and [../NEXTCLOUD.md](../NEXTCLOUD.md) for the runbook.

Two rules for the per-user folders:

- **One SMB share is enough.** Nextcloud connects to the `media` share and
  traverses into `<username>`, so a per-user share adds nothing. Child
  *datasets* are still worth it — they can carry their own snapshot task and
  quota, which a plain folder cannot.
- **A new dataset does not inherit `media`'s ACL** (a new folder does). Check
  the Nextcloud SMB account still has write access — via the `smb_users` group
  in the dataset's Permissions — or its mount will attach but reject uploads.

> **This box is the only thing protecting that data.** Nextcloud does not back
> up SMB external storage — its own Borgbackup covers the database and app
> config only, and the files under `Familia` exist here and nowhere else. The
> Tier 2 items above (Periodic Snapshot Tasks on `hdd-home-1/media` plus a real
> off-box copy) are what stands between a mistaken delete and permanent loss.

## Sources

- [TerraMaster F4-425 Plus review (Neowin)](https://www.neowin.net/reviews/terramaster-f4-425-plus-review-a-modern-low-powered-4k-streamer-home-nas/)
- [Installing TrueNAS on the TerraMaster F4-425 (bitScry)](https://blog.bitscry.com/2025/11/08/installing-truenas-on-terramaster-f4-425/)
- [TerraMaster forum: install TrueNAS on 424/Pro/Max](https://forum.terra-master.com/en/viewtopic.php?t=6751)
- [NAS Compares: TrueNAS on TerraMaster guide](https://nascompares.com/guide/truenas-terramaster-nas-full-installation-guide-2025/)

TrueNAS docs backing the post-install checklist:

- [25.10 (Goldeye) version notes — S.M.A.R.T. service and UI removal](https://www.truenas.com/docs/scale/25.10/gettingstarted/versionnotes/)
- [Managing S.M.A.R.T. Tests (25.04 and earlier flow)](https://www.truenas.com/docs/scale/25.04/scaletutorials/dataprotection/smarttestsscale/)
- [Managing Scrub Tasks](https://www.truenas.com/docs/scale/scaletutorials/dataprotection/scrubtasksscale/)
- [Setting Up System Email](https://www.truenas.com/docs/scale/24.04/scaletutorials/systemsettings/general/settingupsystememail/)
- [Alert Settings](https://www.truenas.com/docs/scale/toptoolbar/alerts/alertsettingsscreen/)
- [Two-Factor Authentication](https://www.truenas.com/docs/scale/22.12/scaletutorials/credentials/2fascale/)
- [Security Recommendations](https://www.truenas.com/docs/solutions/optimizations/security/)
