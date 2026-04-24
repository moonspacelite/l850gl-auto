OpenWrt package for **Fibocom L850-GL** modem management.

Stripped from [QModem](https://github.com/moonspacelite/QModem) (fork of [FUjr/QModem](https://github.com/FUjr/QModem)).

## Supported modes

The Fibocom L850-GL (Intel XMM7360) supports two USB compositions controlled by
`AT+GTUSBMODE`:

| Mode | `AT+GTUSBMODE=` | USB VID:PID   | Kernel driver | Dial backend                 |
|------|-----------------|---------------|---------------|------------------------------|
| NCM  | `0`             | `8087:095a`   | `cdc_ncm`     | AT dial (`AT+CGDATA`)        |
| MBIM | `7`             | `2cb7:0007`   | `cdc_mbim`    | `umbim` over `/dev/cdc-wdmX` |

The active backend is picked automatically from the bound kernel driver
(`get_driver` in `generic.sh`), so you only need to flip the modem between
modes once with `AT+GTUSBMODE=<0|7>; AT+CFUN=15`.

### Switching modes

```
# Switch to MBIM
AT+GTUSBMODE=7
AT+CFUN=15

# Switch back to NCM
AT+GTUSBMODE=0
AT+CFUN=15
```

After `AT+CFUN=15` the modem re-enumerates on USB; `qmodem` picks it up via
hotplug automatically.

## Credits

Based on [QModem](https://github.com/FUjr/QModem) by Siriling & Fujr.
