// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.export;

import 'builder/builder.dart';
import 'builder/library_builder.dart';
import 'combinator.dart' show CombinatorBuilder;

class Export {
  /// The library that is exporting [exported];
  final LibraryBuilder exporter;

  /// The library being exported.
  LibraryBuilder exported;

  final List<CombinatorBuilder>? combinators;

  final int charOffset;

  Export(this.exporter, this.exported, this.combinators, this.charOffset);

  Uri get fileUri => exporter.fileUri;

  bool addToExportScope(String name, Builder member) {
    if (combinators != null) {
      for (CombinatorBuilder combinator in combinators!) {
        if (combinator.isShow && !combinator.names.contains(name)) return false;
        if (combinator.isHide && combinator.names.contains(name)) return false;
      }
    }
    return exporter.addToExportScope(name, member, charOffset);
  }
}
