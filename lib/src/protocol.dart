// Starry frame reassembly + realtime decode.

import 'gatt.dart';

/// Reassembles BLE notification chunks into complete, checksum-valid frames.
/// A frame is `00 00 LEN .. 55 AA .. CHK`; total length = LEN + 4; CHK is the
/// 8-bit additive sum of all preceding bytes. Resynchronises on a bad frame.
class StarryFrameAssembler {
  final List<int> _buf = [];

  List<List<int>> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <List<int>>[];
    while (_buf.length >= 3) {
      final total = _buf[2] + 4;
      if (total < 8 || total > 260) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      final frame = _buf.sublist(0, total);
      final chk = frame.sublist(0, total - 1).fold<int>(0, (a, b) => a + b) & 0xFF;
      // 0x55 0xAA marker sits at indices 5,6 in both request and response.
      if (chk == frame[total - 1] && frame[5] == 0x55 && frame[6] == 0xAA) {
        out.add(frame);
        _buf.removeRange(0, total);
      } else {
        _buf.removeAt(0);
      }
    }
    return out;
  }

  void clear() => _buf.clear();
}

int _u16(List<int> f, int i) => f[i] | (f[i + 1] << 8);
int _i16(List<int> f, int i) {
  final v = _u16(f, i);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int _u32(List<int> f, int i) => f[i] | (f[i + 1] << 8) | (f[i + 2] << 16) | (f[i + 3] << 24);
int _i32(List<int> f, int i) {
  final v = _u32(f, i);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

/// Decoded realtime state from a 0x13 (status) response. Offsets are absolute
/// into the ~105-byte frame; data begins at byte 8, all little-endian.
class StarrySnapshot {
  final List<int> frame;
  StarrySnapshot(this.frame);

  bool get valid => frame.length >= 104 && frame[4] == (cmdRealtime | 0x80);

  double get voltage => _u32(frame, 12) / 1000.0; // battery voltage, mV
  double get current => _i32(frame, 48) / 1000.0; // mA, discharge negative
  int get socPercent => _u16(frame, 90).clamp(0, 100); // %
  double get soh => _u32(frame, 92).toDouble(); // %
  int get cycles => _u32(frame, 96);
  double get remainingAh => _u16(frame, 62) * 0.01;
  double get fullAh => _u16(frame, 64) * 0.01;
  int get balanceMask => _u32(frame, 84);

  /// Per-cell voltages: up to 16 cells at byte 16, u16 mV each; a cell counts
  /// only while its word is non-zero.
  List<double> get cellVoltages {
    final out = <double>[];
    for (var i = 0; i < 16; i++) {
      final mv = _u16(frame, 16 + i * 2);
      if (mv == 0) break;
      out.add(mv / 1000.0);
    }
    return out;
  }

  /// Cell + MOSFET temperatures (°C).
  List<double> get temperaturesC => [_i16(frame, 52).toDouble(), _i16(frame, 54).toDouble()];

  int get statusWord => _u32(frame, 68);
  bool get dischargeMosOn => statusWord & 0x80 == 0; // bit 0x80 = discharge MOS OFF
  int get protectionMask => _u32(frame, 76);
  List<String> get activeProtections => protectionMask != 0 ? const ['Protection active'] : const [];
}
