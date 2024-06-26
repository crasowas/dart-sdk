// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class Interface {
  final int implementedConcreteField = 0;

  abstract final int implementedAbstractField;

  final int declaredConcreteImplementsConcreteField = 0;

  final int declaredAbstractImplementsConcreteField = 0;

  abstract final int declaredConcreteImplementsAbstractField;

  abstract final int declaredAbstractImplementsAbstractField;
}

abstract class AbstractClass implements Interface {
  final int declaredConcreteField = 0;

  abstract final int declaredAbstractField;

  final int declaredConcreteImplementsConcreteField = 0;

  abstract final int declaredAbstractImplementsConcreteField;

  final int declaredConcreteImplementsAbstractField = 0;

  abstract final int declaredAbstractImplementsAbstractField;
}

main() {}
