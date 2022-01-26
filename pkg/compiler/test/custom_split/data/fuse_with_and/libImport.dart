// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file was autogenerated by the pkg/compiler/tool/graph_isomorphizer.dart.
import "package:expect/expect.dart";

/*member: v:member_unit=1{b1, b2, b3, b4}*/
void v(Set<String> u, String name, int bit) {
  Expect.isTrue(u.add(name));
  Expect.equals(name[bit], '1');
}

@pragma('dart2js:noInline')
/*member: f_100_0:member_unit=1{b1, b2, b3, b4}*/
f_100_0(Set<String> u, int b) => v(u, '1000', b);
@pragma('dart2js:noInline')
/*member: f_100_1:member_unit=1{b1, b2, b3, b4}*/
f_100_1(Set<String> u, int b) => v(u, '1001', b);
@pragma('dart2js:noInline')
/*member: f_101_0:member_unit=1{b1, b2, b3, b4}*/
f_101_0(Set<String> u, int b) => v(u, '1010', b);
@pragma('dart2js:noInline')
/*member: f_101_1:member_unit=1{b1, b2, b3, b4}*/
f_101_1(Set<String> u, int b) => v(u, '1011', b);
@pragma('dart2js:noInline')
/*member: f_110_0:member_unit=1{b1, b2, b3, b4}*/
f_110_0(Set<String> u, int b) => v(u, '1100', b);
@pragma('dart2js:noInline')
/*member: f_110_1:member_unit=1{b1, b2, b3, b4}*/
f_110_1(Set<String> u, int b) => v(u, '1101', b);
@pragma('dart2js:noInline')
/*member: f_111_0:member_unit=1{b1, b2, b3, b4}*/
f_111_0(Set<String> u, int b) => v(u, '1110', b);
@pragma('dart2js:noInline')
/*member: f_111_1:member_unit=1{b1, b2, b3, b4}*/
f_111_1(Set<String> u, int b) => v(u, '1111', b);
@pragma('dart2js:noInline')
/*member: f_010_0:member_unit=1{b1, b2, b3, b4}*/
f_010_0(Set<String> u, int b) => v(u, '0100', b);
@pragma('dart2js:noInline')
/*member: f_010_1:member_unit=1{b1, b2, b3, b4}*/
f_010_1(Set<String> u, int b) => v(u, '0101', b);
@pragma('dart2js:noInline')
/*member: f_011_0:member_unit=1{b1, b2, b3, b4}*/
f_011_0(Set<String> u, int b) => v(u, '0110', b);
@pragma('dart2js:noInline')
/*member: f_011_1:member_unit=1{b1, b2, b3, b4}*/
f_011_1(Set<String> u, int b) => v(u, '0111', b);
@pragma('dart2js:noInline')
/*member: f_001_0:member_unit=1{b1, b2, b3, b4}*/
f_001_0(Set<String> u, int b) => v(u, '0010', b);
@pragma('dart2js:noInline')
/*member: f_001_1:member_unit=1{b1, b2, b3, b4}*/
f_001_1(Set<String> u, int b) => v(u, '0011', b);
@pragma('dart2js:noInline')
/*member: f_000_1:member_unit=2{b4}*/
f_000_1(Set<String> u, int b) => v(u, '0001', b);
