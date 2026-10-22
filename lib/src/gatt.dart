// "Starry" BMS protocol (askstarry.com ODM), shared by Power Queen, ANT BMS and
// likely LiTime / Ampere Time. Recovered by static analysis of the Power Queen
// and ANT uni-app bundles. A custom framed protocol over a FFE0 serial service.

const String kServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const String kNotifyUuid = '0000ffe1-0000-1000-8000-00805f9b34fb'; // device -> app
const String kWriteUuid = '0000ffe2-0000-1000-8000-00805f9b34fb'; // app -> device

// Commands (register ids).
const int cmdRegister = 0x01;
const int cmdRealtime = 0x13;
const int cmdSoc = 0x41;
const int cmdCapacity = 0x43;

/// Build a request frame: `00 00 LEN 01 CMD 55 AA [payload] CHK`, where LEN is
/// the byte count from the `01` through the last payload byte, and CHK is the
/// 8-bit additive sum of every preceding byte.
List<int> buildCommand(int cmd, {List<int> payload = const []}) {
  final len = 4 + payload.length; // 01, CMD, 55, AA, payload...
  final body = <int>[0x00, 0x00, len, 0x01, cmd, 0x55, 0xAA, ...payload];
  final chk = body.fold<int>(0, (a, b) => a + b) & 0xFF;
  return [...body, chk];
}
