/// "Starry" BMS driver for bms_core: a custom framed protocol over a FFE0 BLE
/// serial service, shared by Power Queen, ANT BMS and likely LiTime. Read-only
/// live monitoring of cells, temps, current, SOC, SOH, capacity and cycles.
library;

export 'src/battery.dart';
export 'src/gatt.dart';
export 'src/protocol.dart';
