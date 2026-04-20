# l850gl-auto

OpenWrt package for **Fibocom L850-GL** modem management.

Stripped from [QModem](https://github.com/moonspacelite/QModem) (fork of [FUjr/QModem](https://github.com/FUjr/QModem)).

## Supported Device

| Model | USB ID | Platform | Interface | LTE Bands | WCDMA Bands |
|-------|--------|----------|-----------|-----------|-------------|
| Fibocom L850-GL | `8087:095a` | Intel XMM | NCM (cdc_ncm) | B1/2/3/4/5/7/8/12/13/17/18/19/20/25/26/28/66 | B1/2/4/5/8 |

## Build Targets

| Target | Arch |
|--------|------|
| `armsr/armv8` | `aarch64_generic` |
| `ipq40xx/generic` | `arm_cortex-a7_neon-vfpv4` |

## Packages

| Package | Role |
|---------|------|
| `luci-app-qmodem` | Core modem management UI |
| `luci-app-qmodem-sms` | SMS management UI |
| `qmodem` | Backend scripts (dial, scan, ctrl) |
| `tom_modem` | AT command engine (core dependency) |
| `ubus-at-daemon` | AT command ubus bridge |
| `sms-tool_q` | SMS send tool |
| `sms-forwarder` | SMS forwarding daemon |
| `ndisc6` | IPv6 neighbor discovery (conditional) |

## Dial Mechanism (L850GL)

L850GL uses **AT+XDATACHANNEL + AT+CGDATA** (Intel NCM path) — no quectel-CM required.

## Credits

Based on [QModem](https://github.com/FUjr/QModem) by Siriling & Fujr.
