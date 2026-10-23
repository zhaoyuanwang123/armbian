# Xiaomi Mi 10 (umi) — SDX55 外置调制解调器(移动数据)适配

移植自 royka1 的 Xiaomi-Apollo-pmOS-packages(Mi 10T,同一颗 SDX55m
外挂 modem,PCIe2 挂载,MHI + Sahara 加载,QRTR 控制面 / mhi_net 数据面)。

## 目录结构

    modem/
    ├── bin/                          交叉编译的 arm64 二进制(trixie sysroot)
    │   ├── pm_service_native         Peripheral Manager QMI shim(secure NV 前置)
    │   ├── mdm_helper_native         ESOC mdm_helper 替代(AP2MDM 握手 + BOOT_DONE)
    │   ├── mhi_efs_sync              modem 远程 EFS 镜像(替代 Android /vendor/bin/ks)
    │   ├── tqftpserv-sdx55           QRTR RFS/TFTP 服务器,patched: instance 3 + send_retry
    │   ├── diag_reader               modem DIAG 抓取(调试)
    │   └── adsp_diag                 ADSP F3 日志(调试)
    ├── scripts/
    │   ├── umi-efs-extract        从 mdm1m9kefs1/2/3 分区提取本机 NV(8MB/个)
    │   ├── umi-uim-provision      选 USIM 应用(QRTR node 3)
    │   └── umi-mm-restart-once    modem 晚于 MM 出现时重启 MM + 循环注册
    ├── systemd/                      8 个 unit + 2 个 MM drop-in + preset
    ├── udev/                         MM 融合规则(QRTR 控制面 + mhi_net 数据面合并;
    │                                 忽略 wwan0efs0 防 rmts_srv ERRFATAL)
    ├── umi-modem.conf.modules        qrtr/qrtr-mhi/mhi_wwan_ctrl/mhi_net/rmnet
    ├── timesyncd/ dispatcher/        无 RTC 板的 NTP-by-IP 兜底
    └── modemmanager_1.24.0-1+deb13u1umi1_arm64.deb   打了 2 个补丁的 MM

## ModemManager 补丁(对 trixie MM 1.24.0 必需)

1. `0001-qcom-soc-mhi-net`:qcom-soc 插件的 `peek_port_qmi_for_data` 接受
   `mhi_net` 驱动的数据口(否则报 "Unsupported QMI kernel driver")。
2. `0002-bearer-bind-pcie`:endpoint 为 PCIe 时也执行 WDS Bind Mux Data Port
   (否则 Start Network 返回 QMI 错误 70 InvalidOperation)。

补丁后的 MM 以本地 deb 安装并 `apt-mark hold`,防止 apt 升级回退。

## 内核侧(已完成,2026-10-23 整合为正式补丁集)

数据网络(ESOC/MHI fusion/QRTR/WWAN/IPA/PCIe/qpnp-pon)已固化为
`patch/kernel/archive/sm8250-7.2/` 的分组补丁,回放 19/19 干净应用:

- `0500-mhi-host-sdx55-fusion` — MHI host:SDX55M fusion
  (`mhi_qcom_sdx55_fusion_info`,17cb:0306/0x010c,Sahara 加载
  `sdx55m/sbl1.mbn` + `sdx55m/multi_image.mbn`)、fusion channel 配置、
  keepalive/satellite/bl_logger,及 ath11k/ath12k/qaic 回调签名适配。
- `0501-esoc-external-modem-bus` — ESOC 总线与驱动(`qcom,ext-sdx55m`)
  + legacy of_gpio/ipc_logging 头(gpiolib-of 恢复 legacy API)。
- `0502-remoteproc-modem-glue` / `0503-qrtr-wwan-data-path` /
  `0504-ipa-sm8250-modem-data` / `0505-pcie-qcom-modem-support` /
  `0506-qcom-scm-soc-modem-glue` — modem SSR/数据面/加速器/PCIe2/SCM。
- `0507-dts-mdm0-ipa-pcie2` — sm8250.dtsi 的 mdm0/IPA/pcie2_rp 节点
  (pm8150b 的 charger/fg 与 0042 去重);umi DTS 在 `dt/` 直拷。
- `0508-input-qpnp-power-on-modem-reset` — PON 驱动(pon_modem_reset)。
- 内核 config 由 `userpatches/config/kernel/linux-sm8250-current.config`
  覆盖(原片段为基底):MHI_BUS/PCI_GENERIC/SAHARA_MODEM=y,
  MHI_NET/MHI_WWAN_CTRL/WWAN/QRTR=y+QRTR_MHI/RMNET=m,QCOM_IPA=m,
  ESOC 全系 =y,INPUT_QPNP_POWER_ON=y。

## 固件布局(userpatches/overlay/lib/firmware/,随镜像安装)

    sdx55m/                ← 内核 Sahara 查找路径(扁平!勿放 qcom/ 下)
      sbl1.mbn multi_image.mbn aop.mbn tz.mbn hyp.mbn ... mcfg/
      efs{1,2,3}.bin       ← 不随镜像发布!首启由 umi-efs-extract 从
                              设备分区提取(8388608 字节/个,含 IMEI/RF 校准)
    qcom/sm8250/umi/       ← ADSP/CDSP/GPU/IPA 固件(原有)

qcom/sdx55m/modem_pr → /mnt/modemfw/image/modem_pr 的符号链接由
tqftpserv-sdx55.service 的 ExecStartPre 在启动时创建(挂载 modem 分区),
tqftpserv 通过 ESOC remoteproc 的 firmware 属性(qcom/sdx55m/…)解析 RFS 路径。

## 启动链(顺序编码在各 unit 依赖里)

    qrtr-ns → pm-service-native ┐
              mdm-helper-native ┼→ PCIe probe → MHI Sahara → mission mode
              (esoc mdm0 驱动)  ┘        ↓
              tqftpserv-sdx55(RFS: mcfg 等) ↓
              umi-esoc-start(rproc start → ESOC_PWR_ON → AP2MDM 握手)★
                                        ↓
              umi-efs-extract(首启提取 NV)→ mhi-efs-sync(/dev/wwan0efs0)
                                        ↓
              umi-uim-provision(选卡)→ ModemManager(QMAP multiplex 强制)
                                        ↓
              ModemManager-restart-once(兜底:重启 MM / 循环无线电直到注册)

★ 关键发现(2026-10 实机验证):本内核的 esoc remoteproc 非 auto_boot,
  必须显式 `echo start > /sys/class/remoteproc/remoteprocN/state` 才会触发
  "Powerup request from SSR" → ESOC_PWR_ON → MHI 钩子。umi-esoc-start.service
  自动做这件事(按 firmware 名含 sdx55m 匹配 remoteproc,5 次重试)。

## 2026-10-23 实机验证记录(小米10 umi 真机)

- ESOC/MHI/fusion:✅ esoc0 创建、`qcom-sdx55m-fusion` 绑定、Sahara 加载
  sbl1.mbn → mission mode,qrtr node 3 全套 QMI 服务上线
- EFS:✅ 首启自动提取 8388608 字节 × 3,IMEI/RF 校准读取正常
- MM 融合:✅ qcom-soc 插件聚合 qrtr3(qmi) + mhi_hwip0/mhi_swip0(net),
  wwan0efs0/wwan0qmi0 正确 ignored
- WDS bind:✅ qmapmux0.0 创建成功(0002 补丁生效)
- 注册:✅ CHN-CT home / LTE / 信号 70%
- 拨号:❌ `cm error: acl-failure` —— 原因是 **SIM 欠费停机**(数据业务被
  运营商暂停),与适配无关。诊断口诀:三种 ip-type 全部 acl-failure 且
  参数与 attach 档案一致时,先查话费/套餐,再查适配。

## 首启验证清单

    # 1. PCIe/MHI 起来了吗
    sudo dmesg | grep -iE "mhi|sdx55|esoc"        # 期望: mission mode
    lspci | grep Qualcomm                          # 17cb:0306
    # 2. 固件/NV
    ls -l /lib/firmware/sdx55m/efs*.bin            # 必须 8388608 字节
    #   512 字节 = 提取失败,检查 /dev/disk/by-partlabel/mdm1m9kefs1
    # 3. RFS / QRTR
    qrtr-lookup                                    # 期望 node 3 有众多服务
    systemctl status tqftpserv-sdx55               # active, 无 "could not resolve"
    # 4. modem + 数据
    mmcli -L; mmcli -m 0                           # state: registered/connected
    ip link show mhi_hwip0 qmapmux*                # bearer 接口
    # 5. 仍失败时看 DIAG(最真实的 modem 视角)
    sudo diag_reader -o diag.log &                 # 或 journalctl -u pm-service-native

## 已知差异(pmOS → Debian)

- pmos 的 `81-libssc-xiaomi-apollo.rules`(加速度计)未移植,与 modem 无关。
- `adsp_diag` 需要内核 CONFIG_RPMSG_CTRL(pmos 也没开),该功能默认不启用。
- Debian 的 qrtr-tools(1.1)自带 qrtr-ns.service;板配置原本就装了它。
- trixie 的 timesyncd/NM dispatcher 路径与 pmos 相同,原样可用。

## 重新编译这些组件(如需)

工作目录 ~/umi-modem-port/(不在 build 树内):

    fetch-sysroot.sh      # trixie arm64 sysroot + noble 宿主工具(dpkg -x,不动系统)
    src/*.c               # 六个工具,一行 aarch64-linux-gnu-gcc --sysroot=... 即可
    package-mm.sh         # 重新打 MM hybrid deb(源码已含补丁于 src/modemmanager-1.24.0)
    aarch64-cross.ini     # meson 交叉文件
