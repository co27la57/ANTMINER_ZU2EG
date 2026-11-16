# Antminer E7 控制板 —— MIO 引脚定义分析

**目标设备**：`172.25.81.151` (MAC `B6:09:1B:37:F3:86`, hostname `antMiner`)
**SoC**：Xilinx **Zynq UltraScale+ MP (ZynqMP)** — `/proc/device-tree/model` = `ZynqMP BM1794 Control Board`
**compatible**：`xlnx,zynqmp-bm1794-ctl` / `xlnx,zynqmp`
**设备树来源**：编译进内核（`/boot` 为空），运行时经 `/proc/device-tree` 暴露；板上 `/usr/bin/dtc` 反编译得到
**DTB blob**：`running.dtb`（36992 字节），反编译 DTS：`running.dts`（42983 字节）

---

## 1. MIO 控制器节点

```
pinctrl@ff180000 {
    compatible = "xlnx,pinctrl-zynqmp";
    status = "okay";
    reg = <0x0 0xff180000 0x0 0x1000>;
}
```

ZynqMP 的 MIO 控制器基地址 `0xFF180000`。所有外设引脚复用都挂在它下面，以「state group」形式组织，
每组含 `mux`（选择功能）与 `conf`（电气属性：slew-rate / io-standard / bias）。

---

## 2. 各外设的 MIO 分配

### 2.1 显式 MIO 引脚（`pins` 属性，最权威）

| 外设 | 方向 | MIO 引脚 |
|---|---|---|
| UART0 (serial@ff000000) | TX | **MIO31** |
| UART0 (serial@ff000000) | RX | **MIO30** |
| UART1 (serial@ff010000) | TX | **MIO32** |
| UART1 (serial@ff010000) | RX | **MIO33** |
| Ethernet GEM2 (ethernet@ff0d0000) | TX/RGMII | **MIO50, MIO51, MIO56, MIO57, MIO58, MIO59** |
| Ethernet GEM2 (ethernet@ff0d0000) | RX/RGMII | **MIO52, MIO53, MIO54, MIO55, MIO56, MIO57** |

> 注：RGMII TX/RX 复用 MIO50–MIO59（10 组），并额外用 MIO56/MIO57 承担时钟/使能。

### 2.2 通过 pinctrl group 间接定义的引脚

ZynqMP 的 `*_N_grp` 命名中，`N` 即该 group 覆盖的 **MIO 编号**（group 内是连续引脚）。

| State group | Function | 引脚 group | 覆盖 MIO | 状态 |
|---|---|---|---|---|
| `uart0-default` | uart0 | `uart0_7_grp` | MIO7 | okay |
| `uart1-default` | uart1 | `uart1_8_grp` | MIO8 | okay |
| `i2c0-default` | i2c0 | `i2c0_8_grp` | MIO8 | okay |
| `i2c1-default` | i2c1 | `i2c1_9_grp` | MIO9 | okay |
| `sdhci0-default` | sdio0 | `sdio0_0_grp` | MIO0 | **disabled** |
| `sdhci1-default` | sdio1 | `sdio1_4bit_0_1_grp` | MIO1 | okay |
| | | `sdio1_0_wp_grp` | MIO1 (WP) | |
| | | `sdio1_0_cd_grp` | MIO1 (CD) | |
| `gem2-default` | ethernet2 | `ethernet2_0_grp` | MIO0 | okay |
| | mdio2 | `mdio2_0_grp` | MIO0 | okay |
| `gpio-default` | gpio0 | `gpio0_26_grp` … `gpio0_29_grp` | MIO26–29 | okay |
| | | `gpio0_38_grp` … `gpio0_42_grp` | MIO38–42 | |
| | | `gpio0_64_grp` … `gpio0_75_grp` | MIO64–75 | |
| `i2c0-gpio` | gpio1 | `gpio0_33_grp`, `gpio0_34_grp` | MIO33, MIO34 | okay (pinctrl-1) |
| `i2c1-gpio` | gpio1 | `gpio0_35_grp`, `gpio0_36_grp` | MIO35, MIO36 | okay (pinctrl-1) |

---

## 3. MIO 编号 → 用途 总表

```
MIO0      SDIO0 / Ethernet2(RGMII) / MDIO2  (sdhci0 已 disabled)
MIO1      SDIO1 数据线 + WP + CD
MIO7      UART0 (uart0_7_grp)
MIO8      UART1 (uart1_8_grp) / I2C0 (i2c0_8_grp)
MIO9      I2C1 (i2c1_9_grp)
MIO26-29  GPIO0  [gpio-default]
MIO30     UART0 RX
MIO31     UART0 TX
MIO32     UART1 TX
MIO33     UART1 RX  +  GPIO1 (i2c0-gpio, I2C0 复位脚)
MIO34     GPIO1 (i2c0-gpio)
MIO35     GPIO1 (i2c1-gpio)
MIO36     GPIO1 (i2c1-gpio)
MIO38-42  GPIO0  [gpio-default]
MIO50-51  Ethernet2 TX (RGMII)
MIO52-57  Ethernet2 RX (RGMII)
MIO58-59  Ethernet2 TX (RGMII)
MIO64-75  GPIO0  [gpio-default]  ← 12 根，主要给 BM1794 ASIC 控制
```

**未被 DTB 显式占用的 MIO**（自由/由 bootloader 或运行时配置）：
MIO2–6、MIO10–29（部分）、MIO37、MIO43–49、MIO60–63、MIO76–77。
注：MIO0–MIO15 与 MIO16–MIO23 在 ZynqMP 上属不同 bank（低压/高压），本板主要使用 bank1(MIO16–49) 与 bank2(MIO50–77)。

---

## 4. 外设 ↔ pinctrl 绑定关系

| 设备节点 | pinctrl-0 | pinctrl-1 | status | 功能 |
|---|---|---|---|---|
| `serial@ff000000` (UART0) | `uart0-default` | — | okay | 调试串口 (ttyPS0) |
| `serial@ff010000` (UART1) | `uart1-default` | — | okay | 第二路串口 |
| `i2c@ff020000` (I2C0) | `i2c0-default` | `i2c0-gpio` | okay | I2C + GPIO 复位 |
| `i2c@ff030000` (I2C1) | `i2c1-default` | `i2c1-gpio` | okay | I2C + GPIO 复位 |
| `sdhci@ff160000` (SD0) | `sdhci0-default` | — | **disabled** | 未启用 |
| `sdhci@ff170000` (SD1) | `sdhci1-default` | — | okay | microSD 卡 |
| `ethernet@ff0d0000` (GEM2) | `gem2-default` | — | okay | RGMII, phy-mode="rgmii-id" |
| `gpio@ff0a0000` | `gpio-default` | — | okay | 22 根 GPIO |

---

## 5. 电气属性约定

`io-standard` 取值：`<0x1>` = LVCMOS18（1.8V），`<0x0>` = LVCMOS33（3.3V）
`slew-rate`：`<0x1>` = 慢速/无压摆限制（多数低速外设）

| 外设 | io-standard | 备注 |
|---|---|---|
| UART0/UART1 | LVCMOS18 | 1.8V 电平 |
| I2C0/I2C1 | LVCMOS18 | 1.8V + bias-pull-up |
| SDIO1 | LVCMOS33 | 3.3V，WP/CD 上拉 |
| Ethernet2 | LVCMOS33 | 3.3V RGMII |
| GPIO | LVCMOS18 | 1.8V |

---

## 6. 结论

**是的，启动 DTB 里完整定义了各外设的 MIO 引脚。** 具体表现为三种形式：

1. **`pins = "MIOxx"`** — UART0/1 和 Ethernet2 直接点名单个引脚，最明确。
2. **`groups = "<func>_N_grp"`** — 引用 ZynqMP 驱动的预定义 group，`N` 即 MIO 编号。
3. **`gpio0_N_grp`** — 22 根 GPIO 一次性交给 GPIO 控制器。

板子上共 **9 个 pinctrl state group**，覆盖 UART×2、I2C×2、SD×2、Ethernet×1、GPIO×1。
实际启用的引脚：MIO0、1、7、8、9、26–29、30–36、38–42、50–59、64–75。

**值得注意**：MIO64–75 这 12 根 GPIO 数量明显多于其他，很可能是驱动 BM1794 矿机 ASIC 链的
控制信号（时钟使能、复位、供电时序等）。如果要用这块板做自己的 FPGA 实验，这组引脚最值得先研究。
