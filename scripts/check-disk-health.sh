#!/bin/bash
# Quick, non-destructive health validation for spinning disks.
#
# Intended for vetting WD "shuck" drives while they are STILL IN their USB
# enclosure — the retailer return window is the real protection, since shucking
# voids the WD warranty. Reports model, CMR/SMR, SMART health and the counters
# that actually matter, then prints a pass/fail summary.
#
# Nothing here writes to the disk. The long-running destructive burn-in
# commands are printed at the end for you to run deliberately.
#
# Usage:
#   sudo ./scripts/check-disk-health.sh                     # all USB disks
#   sudo ./scripts/check-disk-health.sh /dev/sdb /dev/sdc
#   sudo ./scripts/check-disk-health.sh --short-test /dev/sdb

set -euo pipefail

RUN_SHORT_TEST=false

# WD 3.5" drive-managed SMR models. No 8TB+ WD 3.5" drive is SMR — the 8TB
# WD80EDAZ/WD80EMAZ shucks are helium He10/HC320 CMR despite sharing the
# "EDAZ" suffix with the 4/6TB SMR parts, which is a common false alarm.
SMR_MODELS="WD20EZAZ WD30EZAZ WD40EDAZ WD60EDAZ WD60EMAZ WD60EFAX WD60EZAZ"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\033[0;31m'; C_YLW=$'\033[0;33m'; C_GRN=$'\033[0;32m'
    C_DIM=$'\033[2m';    C_RST=$'\033[0m'
else
    C_RED=""; C_YLW=""; C_GRN=""; C_DIM=""; C_RST=""
fi

# ── Argument parsing ──────────────────────────────────────────────────────────

DEVICES=()
for arg in "$@"; do
    case "$arg" in
        --short-test) RUN_SHORT_TEST=true ;;
        -h|--help)    sed -n '2,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)           echo "❌ Unknown option: $arg" >&2; exit 1 ;;
        *)            DEVICES+=("$arg") ;;
    esac
done

# ── Prerequisites ─────────────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ SMART access needs root. Re-run with: sudo $0 $*"
    exit 1
fi

if ! command -v smartctl >/dev/null 2>&1; then
    echo "❌ 'smartctl' not found. Install with: sudo apt-get install -y smartmontools"
    exit 1
fi

# Default to every USB-attached disk when no device is given.
if [ ${#DEVICES[@]} -eq 0 ]; then
    while read -r name; do
        DEVICES+=("/dev/$name")
    done < <(lsblk -dno NAME,TRAN | awk '$2 == "usb" { print $1 }')

    if [ ${#DEVICES[@]} -eq 0 ]; then
        echo "❌ No USB-attached disks found. Pass a device explicitly, e.g. /dev/sdb"
        exit 1
    fi
    echo "${C_DIM}No devices given — auto-detected USB disks: ${DEVICES[*]}${C_RST}"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# Pull a field from `smartctl -i` output, e.g. "Device Model".
info_field() {
    awk -F: -v key="$2" '$1 == key { sub(/^[ \t]+/, "", $2); print $2; exit }' <<<"$1"
}

# Pull the RAW_VALUE (column 10) of a SMART attribute id; "" when absent.
attr_raw() {
    awk -v id="$2" '$1 == id { print $10; exit }' <<<"$1"
}

# Treat a missing/non-numeric attribute as 0 so arithmetic stays safe.
as_num() {
    case "$1" in
        ''|*[!0-9]*) echo 0 ;;
        *)           echo "$1" ;;
    esac
}

SUMMARY=()
EXIT_CODE=0

# ── Per-device checks ─────────────────────────────────────────────────────────

for dev in "${DEVICES[@]}"; do
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo " $dev"
    echo "═══════════════════════════════════════════════════════════════════"

    if [ ! -b "$dev" ]; then
        echo "❌ Not a block device."
        SUMMARY+=("$dev|-|FAIL|not a block device")
        EXIT_CODE=1
        continue
    fi

    # smartctl 7.x auto-detects most USB bridges; fall back to SAT pass-through
    # for the ones it does not recognise. Exit codes are a bitmask (a stale
    # threshold checksum sets a bit), so never let them abort the script.
    SMART_OPTS=()
    if ! smartctl -i "$dev" >/dev/null 2>&1; then
        if smartctl -i -d sat "$dev" >/dev/null 2>&1; then
            SMART_OPTS=(-d sat)
            echo "${C_DIM}USB bridge needed -d sat pass-through.${C_RST}"
        fi
    fi

    INFO=$(smartctl -i "${SMART_OPTS[@]}" "$dev" 2>&1 || true)

    if ! grep -q "SMART support is: *Enabled" <<<"$INFO"; then
        if grep -qi "Unavailable\|Unknown USB bridge" <<<"$INFO"; then
            echo "❌ SMART is not readable through this USB bridge."
            SUMMARY+=("$dev|-|FAIL|no SMART pass-through")
            EXIT_CODE=1
            continue
        fi
    fi

    MODEL=$(info_field "$INFO" "Device Model")
    [ -n "$MODEL" ] || MODEL=$(info_field "$INFO" "Product")
    FAMILY=$(info_field "$INFO" "Model Family")
    SERIAL=$(info_field "$INFO" "Serial Number")
    CAPACITY=$(info_field "$INFO" "User Capacity")
    ROTATION=$(info_field "$INFO" "Rotation Rate")
    FIRMWARE=$(info_field "$INFO" "Firmware Version")

    echo
    echo "  Model      : ${MODEL:-unknown}"
    echo "  Family     : ${FAMILY:-n/a}"
    echo "  Serial     : ${SERIAL:-n/a}"
    echo "  Capacity   : ${CAPACITY:-n/a}"
    echo "  Rotation   : ${ROTATION:-n/a}"
    echo "  Firmware   : ${FIRMWARE:-n/a}"

    # ── Recording technology ──────────────────────────────────────────────────
    # Model number is the only reliable signal here. Do NOT probe TRIM/discard
    # (lsblk -D, hdparm -I) over USB: bridges synthesise UNMAP support and
    # report it for plain CMR drives, giving a false SMR positive.
    REC_TECH="unknown"
    for smr in $SMR_MODELS; do
        if [[ "$MODEL" == *"$smr"* ]]; then
            REC_TECH="SMR"
            break
        fi
    done
    if [ "$REC_TECH" = "unknown" ] && [[ "$FAMILY" == *"He10"* || "$FAMILY" == *"Ultrastar"* ]]; then
        REC_TECH="CMR"
    fi

    case "$REC_TECH" in
        CMR) echo "  Recording  : ${C_GRN}CMR${C_RST} (helium enterprise platform — safe for NAS/RAID)" ;;
        SMR) echo "  Recording  : ${C_RED}SMR${C_RST} (drive-managed — poor for NAS/RAID rebuilds)" ;;
        *)   echo "  Recording  : ${C_YLW}unknown${C_RST} — check the model against the vendor datasheet" ;;
    esac

    # ── SMART health and attributes ───────────────────────────────────────────

    HEALTH_RAW=$(smartctl -H "${SMART_OPTS[@]}" "$dev" 2>&1 || true)
    if grep -q "PASSED\|OK" <<<"$HEALTH_RAW"; then
        HEALTH="PASSED"
    else
        HEALTH="FAILED"
    fi

    ATTRS=$(smartctl -A "${SMART_OPTS[@]}" "$dev" 2>&1 || true)

    HOURS=$(as_num "$(attr_raw "$ATTRS" 9)")
    REALLOC=$(as_num "$(attr_raw "$ATTRS" 5)")
    PENDING=$(as_num "$(attr_raw "$ATTRS" 197)")
    UNCORR=$(as_num "$(attr_raw "$ATTRS" 198)")
    CRC=$(as_num "$(attr_raw "$ATTRS" 199)")
    SPINRETRY=$(as_num "$(attr_raw "$ATTRS" 10)")
    CYCLES=$(as_num "$(attr_raw "$ATTRS" 12)")
    TEMP=$(as_num "$(attr_raw "$ATTRS" 194)")

    ERRLOG=$(smartctl -l error "${SMART_OPTS[@]}" "$dev" 2>&1 || true)
    SELFTEST=$(smartctl -l selftest "${SMART_OPTS[@]}" "$dev" 2>&1 || true)

    echo
    echo "  ── SMART ──────────────────────────────────────────────────"
    printf '  %-26s %s\n' "Overall health"          "$HEALTH"
    printf '  %-26s %s\n' "Power-on hours (9)"      "$HOURS"
    printf '  %-26s %s\n' "Power cycles (12)"       "$CYCLES"
    printf '  %-26s %s\n' "Reallocated sectors (5)" "$REALLOC"
    printf '  %-26s %s\n' "Pending sectors (197)"   "$PENDING"
    printf '  %-26s %s\n' "Offline uncorrect (198)" "$UNCORR"
    printf '  %-26s %s\n' "UDMA CRC errors (199)"   "$CRC"
    printf '  %-26s %s\n' "Spin retries (10)"       "$SPINRETRY"
    printf '  %-26s %s\n' "Temperature (194)"       "${TEMP}degC"

    # ── Optional 2-minute short self-test ─────────────────────────────────────

    if [ "$RUN_SHORT_TEST" = true ]; then
        echo
        echo "  Running short self-test (~2 min)..."
        smartctl -t short "${SMART_OPTS[@]}" "$dev" >/dev/null 2>&1 || true
        for _ in $(seq 1 40); do
            sleep 10
            PROGRESS=$(smartctl -c "${SMART_OPTS[@]}" "$dev" 2>&1 || true)
            grep -q "previous self-test routine completed\|Self-test routine in progress" \
                <<<"$PROGRESS" || continue
            grep -q "Self-test routine in progress" <<<"$PROGRESS" || break
        done
        SELFTEST=$(smartctl -l selftest "${SMART_OPTS[@]}" "$dev" 2>&1 || true)
    fi

    # ── Verdict ───────────────────────────────────────────────────────────────

    VERDICT="PASS"
    NOTES=()

    [ "$HEALTH" = "PASSED" ]  || { VERDICT="FAIL"; NOTES+=("SMART health FAILED"); }
    [ "$REALLOC" -eq 0 ]      || { VERDICT="FAIL"; NOTES+=("$REALLOC reallocated sectors"); }
    [ "$PENDING" -eq 0 ]      || { VERDICT="FAIL"; NOTES+=("$PENDING pending sectors"); }
    [ "$UNCORR" -eq 0 ]       || { VERDICT="FAIL"; NOTES+=("$UNCORR uncorrectable sectors"); }
    [ "$SPINRETRY" -eq 0 ]    || { VERDICT="FAIL"; NOTES+=("$SPINRETRY spin retries"); }

    if grep -qv "No Errors Logged" <<<"$ERRLOG" && grep -q "ATA Error Count" <<<"$ERRLOG"; then
        VERDICT="FAIL"
        NOTES+=("errors in SMART error log")
    fi

    if grep -qi "Completed: read failure\|Completed: unknown failure\|in progress.*failure" <<<"$SELFTEST"; then
        VERDICT="FAIL"
        NOTES+=("self-test reported failure")
    fi

    if [ "$VERDICT" != "FAIL" ]; then
        [ "$REC_TECH" != "SMR" ] || { VERDICT="WARN"; NOTES+=("SMR — avoid for RAID"); }
        [ "$CRC" -eq 0 ]         || { VERDICT="WARN"; NOTES+=("$CRC CRC errors (cable/bridge)"); }
        [ "$HOURS" -le 100 ]     || { VERDICT="WARN"; NOTES+=("$HOURS power-on hours — used stock?"); }
        [ "$TEMP" -le 45 ]       || { VERDICT="WARN"; NOTES+=("${TEMP}degC — running hot"); }
        if ! grep -q "Completed without error" <<<"$SELFTEST"; then
            VERDICT="WARN"
            NOTES+=("no self-test on record — run --short-test")
        fi
    fi

    NOTE_STR=$(IFS=';'; echo "${NOTES[*]:-all clean}")

    echo
    case "$VERDICT" in
        PASS) echo "  ${C_GRN}✅ PASS${C_RST} — $NOTE_STR" ;;
        WARN) echo "  ${C_YLW}⚠️  WARN${C_RST} — $NOTE_STR" ;;
        FAIL) echo "  ${C_RED}❌ FAIL${C_RST} — $NOTE_STR"; EXIT_CODE=1 ;;
    esac

    SUMMARY+=("$dev|${MODEL:-unknown}|$REC_TECH|$VERDICT|$NOTE_STR")
done

# ── Summary table ─────────────────────────────────────────────────────────────

echo
echo "═══════════════════════════════════════════════════════════════════"
echo " SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"
printf '%-10s %-24s %-5s %-6s %s\n' "DEVICE" "MODEL" "REC" "RESULT" "NOTES"
printf '%-10s %-24s %-5s %-6s %s\n' "──────" "─────" "───" "──────" "─────"
for row in "${SUMMARY[@]}"; do
    IFS='|' read -r s_dev s_model s_rec s_verdict s_notes <<<"$row"
    printf '%-10s %-24s %-5s %-6s %s\n' \
        "$s_dev" "${s_model:0:24}" "$s_rec" "$s_verdict" "$s_notes"
done

# ── Next steps ────────────────────────────────────────────────────────────────

cat <<'EOF'

These checks are quick and non-destructive. Before trusting real data to a
drive, run the full surface validation while it is still in the enclosure and
inside the retailer's return window:

  # Extended self-test — full internal surface scan, ~13 h on 8TB.
  # Runs on the drive itself, so it survives USB bridge hiccups.
  sudo smartctl -t long /dev/sdX
  sudo smartctl -l selftest /dev/sdX      # want "Completed without error"

  # Optional destructive write test. ONE pattern (~30 h on 8TB over USB);
  # the 4-pattern default takes about a week and is rarely worth it.
  sudo badblocks -wsv -t random -b 4096 /dev/sdX

  # Re-read the counters afterwards — 5/197/198 must still be zero.
  sudo smartctl -A /dev/sdX

Keep the machine and the enclosure awake for long runs, or the test dies:

  echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend
  tmux new -s burnin
  sudo systemd-inhibit --what=sleep:idle --why="disk burn-in" \
    badblocks -wsv -t random -b 4096 /dev/sdX

After shucking, mind the SATA 3.3V power-disable pin (PWDIS). The WD80EDAZ
implements it, so any supply feeding 3.3V on pin 3 holds the drive powered off
- it simply never spins up, which is harmless but looks like a dead drive.

Most NAS backplanes omit 3.3V entirely, so test before modifying anything: fit
one drive, power on, check it is detected. Only if it is NOT detected, cover
power pins 1-3 (all three carry 3.3V) with Kapton tape.

Do NOT use molded Molex-to-SATA adapters as a workaround - they are a
documented fire hazard.
EOF

exit "$EXIT_CODE"
