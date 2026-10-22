import 'package:flutter_test/flutter_test.dart';
import 'package:starry_bms/starry_bms.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
void _u16(List<int> f, int i, int v) {
  f[i] = v & 0xFF;
  f[i + 1] = (v >> 8) & 0xFF;
}

void _u32(List<int> f, int i, int v) {
  f[i] = v & 0xFF;
  f[i + 1] = (v >> 8) & 0xFF;
  f[i + 2] = (v >> 16) & 0xFF;
  f[i + 3] = (v >> 24) & 0xFF;
}

List<int> _statusFrame() {
  final f = List<int>.filled(105, 0);
  f[2] = 0x65; // LEN = 101 -> total 105
  f[3] = 0x01;
  f[4] = 0x13 | 0x80; // 0x93
  f[5] = 0x55;
  f[6] = 0xAA;
  f[7] = 0x00;
  _u32(f, 12, 53250); // 53.25 V
  _u16(f, 16, 3300);
  _u16(f, 18, 3310);
  _u16(f, 20, 3290); // 3 cells
  _u32(f, 48, 0x100000000 - 20000); // -20.0 A (i32)
  _u16(f, 52, 25); // cell temp
  _u16(f, 54, 30); // mos temp
  _u16(f, 62, 9210); // 92.1 Ah
  _u16(f, 64, 10000); // 100.0 Ah
  _u32(f, 84, 0x5); // balance cells 1 & 3
  _u16(f, 90, 76); // SOC
  _u32(f, 92, 98); // SOH
  _u32(f, 96, 12); // cycles
  f[104] = f.sublist(0, 104).fold<int>(0, (a, b) => a + b) & 0xFF;
  return f;
}

void main() {
  test('read-realtime request frame + checksum', () {
    expect(_hex(buildCommand(cmdRealtime)), '0000040113 55aa17'.replaceAll(' ', ''));
  });

  test('assembler reassembles a split frame and rejects a bad checksum', () {
    final f = _statusFrame();
    final asm = StarryFrameAssembler();
    expect(asm.add(f.sublist(0, 40)), isEmpty); // partial
    final done = asm.add(f.sublist(40));
    expect(done.length, 1);
    expect(done.first.length, 105);

    final bad = List<int>.of(f)..[104] = (f[104] + 1) & 0xFF;
    expect(StarryFrameAssembler().add(bad), isEmpty);
  });

  test('status frame decodes every field', () {
    final s = StarrySnapshot(_statusFrame());
    expect(s.valid, isTrue);
    expect(s.voltage, closeTo(53.25, 1e-9));
    expect(s.cellVoltages, [3.300, 3.310, 3.290]);
    expect(s.current, closeTo(-20.0, 1e-9));
    expect(s.temperaturesC, [25.0, 30.0]);
    expect(s.remainingAh, closeTo(92.1, 1e-9));
    expect(s.fullAh, closeTo(100.0, 1e-9));
    expect(s.socPercent, 76);
    expect(s.soh, 98);
    expect(s.cycles, 12);
    expect(s.balanceMask, 0x5);
    expect(s.dischargeMosOn, isTrue);
  });

  test('driver advertises FFE0 with SOH + balancing capabilities', () {
    final d = StarryBatteryDriver();
    expect(d.id, 'starry');
    expect(d.signature.services, contains(kServiceUuid));
    expect(d.capabilities.stateOfHealth, isTrue);
    expect(d.capabilities.cellBalancing, isTrue);
    expect(d.capabilities.cycleCount, isTrue);
  });
}
