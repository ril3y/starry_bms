// "Starry" BMS driver for bms_core — Power Queen, ANT BMS, likely LiTime. A
// custom framed protocol over a FFE0 serial service. Read-only live monitoring;
// the pack's FET/heating/power-save/SOH writes are mapped but not implemented.

import 'dart:async';
import 'dart:typed_data';

import 'package:bms_core/bms_core.dart';
import 'package:universal_ble/universal_ble.dart';

import 'gatt.dart';
import 'protocol.dart';

class StarryBatteryDriver extends BatteryDriver {
  @override
  String get id => 'starry';

  @override
  String get name => 'Power Queen / LiTime';

  /// Shares the FFE0 serial service with other families (e.g. JK), so the
  /// connect-time probe confirms it by the response framing.
  @override
  final BleSignature signature = BleSignature(services: [kServiceUuid]);

  @override
  BatteryCapabilities get capabilities => const BatteryCapabilities(
        cells: true,
        cellBalancing: true,
        temperatures: true,
        stateOfHealth: true,
        cycleCount: true,
      );

  @override
  Battery create(BleDevice device) => StarryBattery(device, this);
}

class StarryBattery extends Battery {
  final BleDevice device;
  @override
  final StarryBatteryDriver driver;

  final BleLink _link;
  final StarryFrameAssembler _asm = StarryFrameAssembler();
  final _frames = StreamController<List<int>>.broadcast();
  final _snapshots = StreamController<BatterySnapshot>.broadcast();
  final _cells = StreamController<List<double>>.broadcast();
  StreamSubscription<Uint8List>? _rx;
  Timer? _poll;
  StarrySnapshot? last;

  StarryBattery(this.device, this.driver)
      : _link = BleLink(device,
            service: kServiceUuid, notify: kNotifyUuid, write: kWriteUuid, writeWithResponse: true);

  @override
  String get id => 'starry-${device.deviceId}';

  @override
  String get displayName => device.name?.isNotEmpty == true ? device.name! : 'Power Queen battery';

  @override
  Stream<BatterySnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<List<double>> get cellVoltages => _cells.stream;
  @override
  Stream<bool> get connection => _link.connection;

  @override
  Future<void> connect() async {
    _rx = _link.incoming.listen((chunk) => _asm.add(chunk).forEach(_frames.add));
    await _link.connect();
    // Register to start the data stream (the app does this on connect).
    try {
      await _link.write(Uint8List.fromList(buildCommand(cmdRegister)));
    } catch (_) {}
  }

  /// Write [cmd] and wait for the matching response frame (`cmd | 0x80`).
  Future<List<int>> _exchange(int cmd, {Duration timeout = const Duration(seconds: 3)}) =>
      _link.exclusive(() async {
        final reply = _frames.stream.firstWhere((f) => f.length > 4 && f[4] == (cmd | 0x80)).timeout(timeout);
        await _link.write(Uint8List.fromList(buildCommand(cmd)));
        return reply;
      });

  Future<StarrySnapshot> readSnapshot() async {
    final s = StarrySnapshot(await _exchange(cmdRealtime));
    last = s;
    return s;
  }

  @override
  void startLive() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final s = await readSnapshot();
        if (!s.valid) return;
        _snapshots.add(_toSnapshot(s));
        _cells.add(s.cellVoltages);
      } catch (_) {
        // Retried on the next tick.
      }
    });
  }

  @override
  void stopLive() => _poll?.cancel();

  BatterySnapshot _toSnapshot(StarrySnapshot s) => BatterySnapshot(
        time: DateTime.now(),
        voltage: s.voltage,
        current: s.current,
        soc: s.socPercent,
        remainingAh: s.remainingAh,
        fullAh: s.fullAh > 0 ? s.fullAh : s.remainingAh,
        cycles: s.cycles,
        temperaturesC: s.temperaturesC,
        balanceMask: s.balanceMask,
        activeProtections: s.activeProtections,
        protectionMask: s.protectionMask,
        chargeEnabled: true, // charge-FET bit not identified in the protocol
        dischargeEnabled: s.dischargeMosOn,
      );

  @override
  Future<BatteryIdentity> identify() async {
    final s = last ?? await readSnapshot();
    return BatteryIdentity(
      serial: device.name,
      cellCount: s.cellVoltages.length,
      nominalVoltage: s.cellVoltages.length * 3.2,
      soc: s.socPercent,
    );
  }

  @override
  Future<HealthReport?> readHealth() async {
    final s = last ?? await readSnapshot();
    return HealthReport(
      cycles: s.cycles,
      fullChargeAh: s.fullAh > 0 ? s.fullAh : null,
      reportedSoh: s.soh > 0 ? s.soh / 100 : null,
    );
  }

  @override
  Future<List<BatteryNotice>> notices() async => const [];

  @override
  Future<void> disconnect() async {
    stopLive();
    await _rx?.cancel();
    await _link.disconnect();
  }
}
