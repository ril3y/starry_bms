# starry_bms

"Starry" BMS driver for [bms_core](https://github.com/ril3y/bms_core) — the
shared protocol behind several Amazon LiFePO4 brands (**Power Queen, ANT BMS,
and likely LiTime / Ampere Time**; backend `askstarry.com`).

A custom framed protocol over a BLE serial service (service FFE0, notify FFE1,
write FFE2): request `00 00 LEN 01 CMD 55 AA … CHK` (8-bit additive checksum).
The 0x13 realtime response decodes to per-cell voltages, cell + MOSFET
temperatures, pack voltage/current, SOC, SOH, remaining/full capacity, cycle
count, per-cell balancing and discharge-FET state.

Read-only in this release. Protocol recovered by static analysis for
interoperability; not affiliated with any brand.

## License

MIT.
