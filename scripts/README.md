# Operational scripts

Standalone helpers that sit outside the Packer → Terraform → Ansible pipeline.

## check-disk-health.sh

Quick, non-destructive SMART validation for spinning disks. Written for vetting
WD "shuck" drives **while they are still in their USB enclosure** — shucking
voids the WD warranty, so the retailer's return window is the real protection
and all testing should happen before the enclosure is opened.

```bash
sudo ./scripts/check-disk-health.sh                     # all USB-attached disks
sudo ./scripts/check-disk-health.sh /dev/sdb /dev/sdc
sudo ./scripts/check-disk-health.sh --short-test /dev/sdb
```

Requires `smartmontools` (`sudo apt-get install -y smartmontools`) and root.
Exit code is non-zero if any drive fails.

### What it checks

| Check | Fails on |
|---|---|
| SMART overall health | not `PASSED` |
| Reallocated sectors (5) | any non-zero |
| Pending sectors (197) | any non-zero |
| Offline uncorrectable (198) | any non-zero |
| Spin retries (10) | any non-zero |
| SMART error log | any logged ATA error |
| Self-test log | a recorded read/unknown failure |

Warnings (not failures) cover SMR drives, non-zero UDMA CRC errors, a
power-on-hours count above 100 (suggesting used stock sold as new), a
temperature above 45 °C, and the absence of any self-test on record.

### CMR vs SMR

The script decides from the **model number only**. Do not probe TRIM/discard
(`lsblk -D`, `hdparm -I`) through a USB bridge: bridges synthesise UNMAP support
and report it for plain CMR drives, producing a false SMR positive.

No 8 TB or larger WD 3.5" drive is SMR. The 8 TB `WD80EDAZ`/`WD80EMAZ` shucks
are helium He10/HC320 CMR, despite sharing the `EDAZ` suffix with the 4/6 TB SMR
parts — a common source of false alarms in forum threads.

### After the quick pass

The script prints the follow-up commands: an extended self-test (~13 h on 8 TB,
runs on-drive so it survives USB dropouts), an optional single-pattern
`badblocks` write test, and the `systemd-inhibit` / USB-autosuspend settings
needed to stop a laptop killing a multi-day run.

### The SATA 3.3 V power-disable pin

The 8 TB `WD80EDAZ` implements PWDIS on power pin 3, so any supply that feeds
3.3 V there holds the drive powered off. It never spins up and is not detected —
harmless, fully reversible, but it looks exactly like a dead drive.

Most NAS backplanes omit 3.3 V entirely, so **test before modifying anything**:
fit one drive, power on, and check whether it is detected. Only if it is not,
cover power pins 1-3 (all three carry 3.3 V) with Kapton tape.

Never use molded Molex-to-SATA adapters as a workaround — they are a documented
fire hazard.
