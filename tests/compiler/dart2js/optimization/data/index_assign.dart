// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.7

/*member: dynamicIndexAssign:Specializer=[!IndexAssign]*/
@pragma('dart2js:noInline')
dynamicIndexAssign(var list) {
  list[0] = 1;
}

/*strong.member: unknownListIndexAssign:Specializer=[!IndexAssign]*/
/*omit.member: unknownListIndexAssign:Specializer=[IndexAssign]*/
@pragma('dart2js:noInline')
unknownListIndexAssign(List list) {
  list[0] = 1;
}

/*strong.member: possiblyNullMutableListIndexAssign:Specializer=[!IndexAssign]*/
/*omit.member: possiblyNullMutableListIndexAssign:Specializer=[IndexAssign]*/
@pragma('dart2js:noInline')
possiblyNullMutableListIndexAssign(bool b) {
  var list = b ? [0] : null;
  list[0] = 1;
}

/*strong.member: mutableListIndexAssign:Specializer=[!IndexAssign]*/
/*omit.member: mutableListIndexAssign:Specializer=[IndexAssign]*/
@pragma('dart2js:noInline')
mutableListIndexAssign() {
  var list = [0];
  list[0] = 1;
}

/*strong.member: mutableListDynamicIndexAssign:Specializer=[!IndexAssign]*/
/*omit.member: mutableListDynamicIndexAssign:Specializer=[IndexAssign]*/
@pragma('dart2js:noInline')
mutableListDynamicIndexAssign(dynamic index) {
  var list = [0];
  list[index] = 1;
}

/*strong.member: mutableListDynamicValueIndexAssign:Specializer=[!IndexAssign]*/
/*omit.member: mutableListDynamicValueIndexAssign:Specializer=[IndexAssign]*/
@pragma('dart2js:noInline')
mutableListDynamicValueIndexAssign(dynamic value) {
  var list = [0];
  list[0] = value;
}

/*member: immutableListIndexAssign:Specializer=[!IndexAssign]*/
@pragma('dart2js:noInline')
immutableListIndexAssign() {
  var list = const [0];
  list[0] = 1;
}

main() {
  dynamicIndexAssign([]);
  dynamicIndexAssign({});
  unknownListIndexAssign([]);
  unknownListIndexAssign(null);
  possiblyNullMutableListIndexAssign(true);
  possiblyNullMutableListIndexAssign(false);
  mutableListIndexAssign();
  mutableListDynamicIndexAssign(0);
  mutableListDynamicIndexAssign('');
  mutableListDynamicValueIndexAssign(0);
  mutableListDynamicValueIndexAssign('');
  immutableListIndexAssign();
}
