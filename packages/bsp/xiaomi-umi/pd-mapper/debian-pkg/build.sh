#!/bin/bash
# Build the umi-pd-mapper deb (cross-compiled pd-mapper + libqrtr).
# Source: linux-msm/pd-mapper + linux-msm/qrtr, aarch64 cross build.
set -euo pipefail
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-/home/zhao/build/output/debs}"
VER="1.0-umi1"
STAGE="$(mktemp -d /tmp/umi-pdmapper-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DEBIAN"; chmod 755 "$STAGE"
install -Dm755 /tmp/pd-mapper/pd-mapper "$STAGE/usr/bin/pd-mapper"
install -Dm644 "$PKG_DIR/pd-mapper.service" "$STAGE/usr/lib/systemd/system/pd-mapper.service"
install -m755 "$PKG_DIR/postinst" "$STAGE/DEBIAN/postinst"
install -m755 "$PKG_DIR/prerm"    "$STAGE/DEBIAN/prerm"
install -m755 "$PKG_DIR/postrm"   "$STAGE/DEBIAN/postrm"
install -m644 "$PKG_DIR/control"  "$STAGE/DEBIAN/control"
mkdir -p "$OUT_DIR"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT_DIR/umi-pd-mapper_${VER}_arm64.deb" >/dev/null
echo "Built: $OUT_DIR/umi-pd-mapper_${VER}_arm64.deb"
