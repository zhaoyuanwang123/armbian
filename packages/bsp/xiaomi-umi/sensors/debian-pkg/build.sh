#!/bin/bash
# Build the one-shot "umi-sensors" deb.
#
# Packages everything the sensor BSP hooks in config/boards/xiaomi-umi.conf
# install (hexagonrpcd-umi + units + drop-ins + HexagonFS registry tree)
# plus the kernel-side glue (mount-matrix udev rule, fastrpc modules-load),
# so an already-built trixie rootfs only needs:
#     dpkg -i umi-sensors_*.deb
# after flashing the 7.2.11-Sa2de-D0000-Pb69e (or newer) kernel/dtb debs.
#
# Usage: build.sh [output-dir]   (default: ~/build/output/debs)
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # .../debian-pkg
SENSORS_DIR="$(dirname "$PKG_DIR")"                          # .../sensors
OUT_DIR="${1:-/home/zhao/build/output/debs}"

PKG="umi-sensors"
VER="1.0-umi3"
STAGE="$(mktemp -d /tmp/umi-sensors-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/DEBIAN"
chmod 755 "$STAGE"   # mktemp -d is 0700; keep the deb's root entry sane

# --- daemon + library (arm64, built against trixie glibc) -------------------
install -Dm755 "$SENSORS_DIR/bin/hexagonrpcd-umi" \
	"$STAGE/usr/bin/hexagonrpcd-umi"
install -Dm755 "$SENSORS_DIR/bin/chrecd" \
	"$STAGE/usr/bin/chrecd"
install -Dm755 "$SENSORS_DIR/lib/libhexagonrpc.so.0.4" \
	"$STAGE/usr/lib/libhexagonrpc.so.0.4"

# --- systemd units + umi drop-ins -------------------------------------------
# sdsp is the one that serves on umi; the two adsp units are shipped for
# layout parity and self-disable via ConditionPathExists=!/dev/fastrpc-sdsp.
for u in hexagonrpcd-sdsp hexagonrpcd-adsp-rootpd hexagonrpcd-adsp-sensorspd; do
	install -Dm644 "$SENSORS_DIR/systemd/$u.service" \
		"$STAGE/usr/lib/systemd/system/$u.service"
	install -Dm644 "$SENSORS_DIR/systemd/$u.service.d/10-umi.conf" \
		"$STAGE/usr/lib/systemd/system/$u.service.d/10-umi.conf"
done

# --- HexagonFS root: sensor registry / config tree from stock firmware ------
mkdir -p "$STAGE/usr/share/qcom/sm8250/Xiaomi"
cp -a "$SENSORS_DIR/firmware/sm8250/Xiaomi/umi" \
	"$STAGE/usr/share/qcom/sm8250/Xiaomi/"

# --- kernel-side glue --------------------------------------------------------
install -Dm644 "$SENSORS_DIR/udev/60-fastrpc-umi.rules" \
	"$STAGE/usr/lib/udev/rules.d/60-fastrpc-umi.rules"
install -Dm644 "$SENSORS_DIR/udev/81-libssc-xiaomi-umi.rules" \
	"$STAGE/usr/lib/udev/rules.d/81-libssc-xiaomi-umi.rules"
install -Dm644 "$SENSORS_DIR/modules-load/umi-sensors.conf" \
	"$STAGE/usr/lib/modules-load.d/umi-sensors.conf"

# NB: the legacy OpenRC-style /etc/conf.d/hexagonrpcd-sdsp is NOT shipped
# here — armbian-bsp-cli-xiaomi-umi-current already owns that path and a
# duplicate would make dpkg refuse the install. It is unused on systemd.

# --- maintainer scripts -------------------------------------------------------
install -m755 "$PKG_DIR/postinst" "$STAGE/DEBIAN/postinst"
install -m755 "$PKG_DIR/prerm"    "$STAGE/DEBIAN/prerm"
install -m755 "$PKG_DIR/postrm"   "$STAGE/DEBIAN/postrm"
install -m644 "$PKG_DIR/control"  "$STAGE/DEBIAN/control"

# --- build ---------------------------------------------------------------------
mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group --build "$STAGE" \
	"$OUT_DIR/${PKG}_${VER}_arm64.deb" >/dev/null

echo "Built: $OUT_DIR/${PKG}_${VER}_arm64.deb"
