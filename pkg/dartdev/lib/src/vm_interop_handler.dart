// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

/// Contains methods used to communicate DartDev results back to the VM.
///
/// Messages are received in runtime/bin/dartdev_isolate.cc.
abstract class VmInteropHandler {
  /// Initializes [VmInteropHandler] to utilize [port] to communicate with the
  /// VM.
  static void initialize(SendPort? port) => _port = port;

  /// Notifies the VM to run [script] with [args] upon DartDev exit.
  ///
  /// If [packageConfigOverride] is given, that is where the packageConfig is found.
  ///
  /// If [markMainIsolateAsSystemIsolate] is given and set to true, the spawned
  /// isolate will run with `--mark-main-isolate-as-system-isolate` enabled.
  static void run(
    String script,
    List<String> args, {
    String? packageConfigOverride,
    // TODO(bkonyi): remove once DartDev moves to AOT and this flag can be
    // provided directly to the process spawned by `dart run` and `dart test`.
    //
    // See https://github.com/dart-lang/sdk/issues/53576
    bool markMainIsolateAsSystemIsolate = false,
  }) {
    final port = _port;
    if (port == null) return;
    final message = <dynamic>[
      _kResultRun,
      script,
      packageConfigOverride,
      markMainIsolateAsSystemIsolate,
      // Copy the list so it doesn't get GC'd underneath us.
      args.toList()
    ];
    port.send(message);
  }

  /// Notifies the VM that DartDev has completed running. If provided a
  /// non-zero [exitCode], the VM will terminate with the given exit code.
  static void exit(int? exitCode) {
    final port = _port;
    if (port == null) return;
    final message = <dynamic>[_kResultExit, exitCode];
    port.send(message);
  }

  // Note: keep in sync with runtime/bin/dartdev_isolate.h
  static const int _kResultRun = 1;
  static const int _kResultExit = 2;

  static SendPort? _port;
}
