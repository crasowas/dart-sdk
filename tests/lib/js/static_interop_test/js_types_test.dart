// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Check that JS types work.

// ignore: IMPORT_INTERNAL_LIBRARY
import 'dart:_js_interop';
import 'dart:typed_data';

import 'package:expect/minitest.dart';
import 'package:js/js.dart';

@JS()
external void eval(String code);

@JS()
external JSAny any;

@JS()
external JSObject obj;

@JS()
@staticInterop
class SimpleObject {}

extension SimpleObjectExtension on SimpleObject {
  external JSString get foo;
}

@JS()
external JSFunction fun;

@JS('fun')
external JSString doFun(JSString a, JSString b);

@JS()
external JSExportedDartFunction edf;

@JS()
external JSArray arr;

@JS()
external JSExportedDartObject edo;

@JS()
external JSArrayBuffer buf;

@JS()
external JSDataView dat;

@JS()
external JSTypedArray tar;

@JS()
external JSInt8Array ai8;

@JS()
external JSUint8Array au8;

@JS()
external JSUint8ClampedArray ac8;

@JS()
external JSInt16Array ai16;

@JS()
external JSUint16Array au16;

@JS()
external JSInt32Array ai32;

@JS()
external JSUint32Array au32;

@JS()
external JSFloat32Array af32;

@JS()
external JSFloat64Array af64;

@JS()
external JSNumber nbr;

@JS()
external JSBoolean boo;

@JS()
external JSString str;

class DartObject {
  String get foo => 'bar';
}

void main() {
  eval('''
    globalThis.obj = {
      'foo': 'bar',
    };
    globalThis.fun = function(a, b) {
      return globalThis.edf(a, b);
    }
  ''');

  // [JSObject]
  expect(obj is JSObject, true);
  expect((obj as SimpleObject).foo.toDart(), 'bar');

  // [JSFunction]
  expect(fun is JSFunction, true);

  // [JSExportedDartFunction] <-> [Function]
  edf = (JSString a, JSString b) {
    return (a.toDart() + b.toDart()).toJS();
  }.toJS<JSString Function(JSString, JSString)>();
  expect(doFun('foo'.toJS(), 'bar'.toJS()).toDart(), 'foobar');

  // [JSExportedDartObject] <-> [Object]
  edo = DartObject().toJS();
  expect(edo is JSExportedDartObject, true);
  expect(edo.toDart<DartObject>().foo, 'bar');

  // [JSArray] <-> [List<JSAny?>]
  arr = [1.0.toJS(), 'foo'.toJS()].toJS();
  expect(arr is JSArray, true);
  List<JSAny?> dartArr = arr.toDart();
  expect((dartArr[0] as JSNumber).toDart(), 1.0);
  expect((dartArr[1] as JSString).toDart(), 'foo');

  // [ArrayBuffer] <-> [ByteBuffer]
  buf = Uint8List.fromList([0, 255, 0, 255]).buffer.toJS();
  expect(buf is JSArrayBuffer, true);
  ByteBuffer dartBuf = buf.toDart();
  expect(dartBuf.asUint8List(), equals([0, 255, 0, 255]));

  // [DataView] <-> [ByteData]
  dat = Uint8List.fromList([0, 255, 0, 255]).buffer.asByteData().toJS();
  expect(dat is JSDataView, true);
  ByteData dartDat = dat.toDart();
  expect(dartDat.getUint8(0), 0);
  expect(dartDat.getUint8(1), 255);

  // [TypedArray]s <-> [TypedData]s
  // Int8
  ai8 = Int8List.fromList([-128, 0, 127]).toJS();
  expect(ai8 is JSInt8Array, true);
  Int8List dartAi8 = ai8.toDart();
  expect(dartAi8, equals([-128, 0, 127]));

  // Uint8
  au8 = Uint8List.fromList([-1, 0, 255, 256]).toJS();
  expect(au8 is JSUint8Array, true);
  Uint8List dartAu8 = au8.toDart();
  expect(dartAu8, equals([255, 0, 255, 0]));

  // Uint8Clamped
  ac8 = Uint8ClampedList.fromList([-1, 0, 255, 256]).toJS();
  expect(ac8 is JSUint8ClampedArray, true);
  Uint8ClampedList dartAc8 = ac8.toDart();
  expect(dartAc8, equals([0, 0, 255, 255]));

  // Int16
  ai16 = Int16List.fromList([-32769, -32768, 0, 32767, 32768]).toJS();
  expect(ai16 is JSInt16Array, true);
  Int16List dartAi16 = ai16.toDart();
  expect(dartAi16, equals([32767, -32768, 0, 32767, -32768]));

  // Uint16
  au16 = Uint16List.fromList([-1, 0, 65535, 65536]).toJS();
  expect(au16 is JSUint16Array, true);
  Uint16List dartAu16 = au16.toDart();
  expect(dartAu16, equals([65535, 0, 65535, 0]));

  // Int32
  ai32 = Int32List.fromList([-2147483648, 0, 2147483647]).toJS();
  expect(ai32 is JSInt32Array, true);
  Int32List dartAi32 = ai32.toDart();
  expect(dartAi32, equals([-2147483648, 0, 2147483647]));

  // Uint32
  au32 = Uint32List.fromList([-1, 0, 4294967295, 4294967296]).toJS();
  expect(au32 is JSUint32Array, true);
  Uint32List dartAu32 = au32.toDart();
  expect(dartAu32, equals([4294967295, 0, 4294967295, 0]));

  // Float32
  af32 = Float32List.fromList([-1000.488, -0.00001, 0.0001, 10004.888]).toJS();
  expect(af32 is JSFloat32Array, true);
  Float32List dartAf32 = af32.toDart();
  expect(dartAf32,
      equals(Float32List.fromList([-1000.488, -0.00001, 0.0001, 10004.888])));

  // Float64
  af64 = Float64List.fromList([-1000.488, -0.00001, 0.0001, 10004.888]).toJS();
  expect(af64 is JSFloat64Array, true);
  Float64List dartAf64 = af64.toDart();
  expect(dartAf64, equals([-1000.488, -0.00001, 0.0001, 10004.888]));

  // [JSNumber] <-> [double]
  nbr = 4.5.toJS();
  expect(nbr is JSNumber, true);
  double dartNbr = nbr.toDart();
  expect(dartNbr, 4.5);

  // [JSBoolean] <-> [bool]
  boo = true.toJS();
  expect(boo is JSBoolean, true);
  bool dartBoo = boo.toDart();
  expect(dartBoo, true);

  // [JSString] <-> [String]
  str = 'foo'.toJS();
  expect(str is JSString, true);
  String dartStr = str.toDart();
  expect(dartStr, 'foo');
}
