#!/bin/bash
set -e

# ============ 1. 拷贝自定义固件 ============
OVERLAY_SRC="${SDCARD}/tmp/overlay"

echo ">>> [customize] SDCARD=${SDCARD}"
echo ">>> [customize] 检查 overlay 挂载点: ${OVERLAY_SRC}"
ls -la "${OVERLAY_SRC}" || true

if [[ -d "${OVERLAY_SRC}/lib/firmware" ]]; then
    echo ">>> [customize] 拷贝固件到 /lib/firmware"
    mkdir -p "${SDCARD}/lib/firmware"
    cp -av "${OVERLAY_SRC}/lib/firmware/." "${SDCARD}/lib/firmware/"
else
    echo ">>> [customize] WARNING: ${OVERLAY_SRC}/lib/firmware 不存在"
fi
# ============ 2. 精简 firmware ============
echo ">>> [customize] 精准精简 /lib/firmware (保留小米10专属固件)"

FW_DIR=$(readlink -f "${SDCARD}/lib/firmware")
if [[ -d "$FW_DIR" ]]; then

    # 2.1 删除明确无关的大目录 (包括之前误删的 WiFi/BT 目录)
    for d in \
        intel nvidia amdgpu i915 \
        mellanox netronome liquidio cavium \
        dpaa2 qed qlogic cxgb3 cxgb4 \
        mrvl mediatek \
        ath10k ath12k brcm \
        rtw88 rtw89 rtl_nic rtlwifi rtl_bt \
        iwlwifi mwl8k libertas \
        ixp4xx ti-connectivity ti-keystone \
        Lontium rockchip inside-secure wfx \
        powervr amdnpu amdtee cnm; do
        rm -rf "$FW_DIR/$d"
    done

    # 2.2 在 ath11k 目录内，只保留 QCA6390
    if [[ -d "$FW_DIR/ath11k" ]]; then
        find "$FW_DIR/ath11k" -mindepth 1 -maxdepth 1 -type d \
            ! -name "QCA6390" -exec rm -rf {} + 2>/dev/null || true
    fi

    # 2.3 在 qca 目录内，只保留 QCA6390 蓝牙所需的固件
    # (QCA6390 蓝牙使用的是 htbtfw20.tlv 和 htnv20.bin)
    if [[ -d "$FW_DIR/qca" ]]; then
        find "$FW_DIR/qca" -mindepth 1 -maxdepth 1 -type f \
            ! -name "htbtfw20.tlv" \
            ! -name "htnv20.bin" \
            -delete 2>/dev/null || true
    fi

    # 2.4 删除根目录下不需要的散装固件 (保留 regulatory.db 和自定义文件)
    find "$FW_DIR" -mindepth 1 -maxdepth 1 -type f \
        ! -name "regulatory.db*" \
        ! -name "st_fts*" \
        ! -name "stm_fts*" \
        ! -name "cs35l41*" \
        -delete 2>/dev/null || true

    # 2.5 清理空目录
    find "$FW_DIR" -type d -empty -delete 2>/dev/null || true

    echo ">>> [customize] 精简后 firmware 大小："
    du -sh "$FW_DIR"
fi

echo ">>> [customize] 配置 WiFi 自动连接 (ZZzzx)"

WIFI_SSID="ZZzzx"
WIFI_PASS="17708707858zzx"
WIFI_IFACE="wlp1s0"

# 6.1 wpa_supplicant 兜底配置（Debian / systemd-networkd 用）
mkdir -p "${SDCARD}/etc/wpa_supplicant"
cat > "${SDCARD}/etc/wpa_supplicant/wpa_supplicant.conf" <<EOF
country=CN
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PASS}"
    key_mgmt=WPA-PSK
    priority=10
}
EOF
chmod 600 "${SDCARD}/etc/wpa_supplicant/wpa_supplicant.conf"

# 6.2 NetworkManager 连接配置（Ubuntu / Noble 用）
NM_DIR="${SDCARD}/etc/NetworkManager/system-connections"
mkdir -p "${NM_DIR}"

cat > "${NM_DIR}/${WIFI_SSID}.nmconnection" <<EOF
[connection]
id=${WIFI_SSID}
uuid=$(uuidgen 2>/dev/null || echo "11111111-2222-3333-4444-555555555555")
type=wifi
autoconnect=true
autoconnect-priority=100
interface-name=${WIFI_IFACE}

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASS}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chmod 600 "${NM_DIR}/${WIFI_SSID}.nmconnection"

# 6.3 确保 NetworkManager 开机自启（Ubuntu/Debian 装了就有）
if [[ -d "${SDCARD}/etc/systemd/system" ]]; then
    mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
    if [[ -f "${SDCARD}/usr/lib/systemd/system/NetworkManager.service" ]]; then
        ln -sf /usr/lib/systemd/system/NetworkManager.service \
            "${SDCARD}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
    fi
fi

# 6.4 确保 wpa_supplicant 自启（systemd-networkd 场景）
if [[ -f "${SDCARD}/usr/lib/systemd/system/wpa_supplicant.service" ]]; then
    mkdir -p "${SDCARD}/etc/systemd/system/multi-user.target.wants"
    ln -sf /usr/lib/systemd/system/wpa_supplicant.service \
        "${SDCARD}/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service"
fi

echo ">>> [customize] WiFi 配置完成"
echo ">>> [customize] 完成"

# 把 fstab 里的根分区改成 PARTLABEL=linux
if [[ -f /etc/fstab ]]; then
    sed -i -E 's|^UUID=[^[:space:]]+([[:space:]]+/[[:space:]])|PARTLABEL=linux\1|' /etc/fstab
fi