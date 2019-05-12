// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/declared_variables.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart' show CompilationUnit;
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/inheritance_manager2.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/type_system.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/summary_sdk.dart';
import 'package:analyzer/src/summary2/ast_binary_writer.dart';
import 'package:analyzer/src/summary2/builder/source_library_builder.dart';
import 'package:analyzer/src/summary2/linked_bundle_context.dart';
import 'package:analyzer/src/summary2/linked_element_factory.dart';
import 'package:analyzer/src/summary2/linking_bundle_context.dart';
import 'package:analyzer/src/summary2/reference.dart';
import 'package:analyzer/src/summary2/simply_bounded.dart';
import 'package:analyzer/src/summary2/top_level_inference.dart';
import 'package:analyzer/src/summary2/type_alias.dart';
import 'package:analyzer/src/summary2/types_builder.dart';

var timerLinkingLinkingBundle = Stopwatch();
var timerLinkingRemoveBundle = Stopwatch();

LinkResult link(
  LinkedElementFactory elementFactory,
  List<LinkInputLibrary> inputLibraries,
) {
  var linker = Linker(elementFactory);
  linker.link(inputLibraries);
  return LinkResult(linker.linkingBundle);
}

class Linker {
  final LinkedElementFactory elementFactory;

  LinkedNodeBundleBuilder linkingBundle;
  LinkedBundleContext bundleContext;
  LinkingBundleContext linkingBundleContext;

  /// Libraries that are being linked.
  final Map<Uri, SourceLibraryBuilder> builders = {};

  InheritanceManager2 inheritance; // TODO(scheglov) cache it

  Linker(this.elementFactory) {
    var dynamicRef = rootReference.getChild('dart:core').getChild('dynamic');
    dynamicRef.element = DynamicElementImpl.instance;
    var neverRef = rootReference.getChild('dart:core').getChild('Never');
    neverRef.element = NeverElementImpl.instance;

    linkingBundleContext = LinkingBundleContext(dynamicRef);

    bundleContext = LinkedBundleContext.forAst(
      elementFactory,
      linkingBundleContext.references,
    );
  }

  InternalAnalysisContext get analysisContext {
    return elementFactory.analysisContext;
  }

  FeatureSet get contextFeatures {
    return analysisContext.analysisOptions.contextFeatures;
  }

  DeclaredVariables get declaredVariables {
    return analysisContext.declaredVariables;
  }

  Reference get rootReference => elementFactory.rootReference;

  TypeProvider get typeProvider => analysisContext.typeProvider;

  Dart2TypeSystem get typeSystem => analysisContext.typeSystem;

  void link(List<LinkInputLibrary> inputLibraries) {
    for (var inputLibrary in inputLibraries) {
      SourceLibraryBuilder.build(this, inputLibrary);
    }
    // TODO(scheglov) do in build() ?
    elementFactory.addBundle(bundleContext);

    _buildOutlines();

    timerLinkingLinkingBundle.start();
    _createLinkingBundle();
    timerLinkingLinkingBundle.stop();

    timerLinkingRemoveBundle.start();
    linkingBundleContext.clearIndexes();
    elementFactory.removeBundle(bundleContext);
    timerLinkingRemoveBundle.stop();
  }

  void _buildOutlines() {
    _resolveUriDirectives();
    _computeLibraryScopes();
    _createTypeSystem();
    _resolveTypes();
    TypeAliasSelfReferenceFinder().perform(this);
    _createLoadLibraryFunctions();
    _performTopLevelInference();
    _resolveConstructors();
    _resolveConstantInitializers();
    _resolveDefaultValues();
    _resolveMetadata();
    _collectMixinSuperInvokedNames();
  }

  void _collectMixinSuperInvokedNames() {
    for (var library in builders.values) {
      library.collectMixinSuperInvokedNames();
    }
  }

  void _computeLibraryScopes() {
    for (var library in builders.values) {
      library.addLocalDeclarations();
    }

    for (var library in builders.values) {
      library.buildInitialExportScope();
    }

    var exporters = new Set<SourceLibraryBuilder>();
    var exportees = new Set<SourceLibraryBuilder>();

    for (var library in builders.values) {
      library.addExporters();
    }

    for (var library in builders.values) {
      if (library.exporters.isNotEmpty) {
        exportees.add(library);
        for (var exporter in library.exporters) {
          exporters.add(exporter.exporter);
        }
      }
    }

    var both = new Set<SourceLibraryBuilder>();
    for (var exported in exportees) {
      if (exporters.contains(exported)) {
        both.add(exported);
      }
      for (var export in exported.exporters) {
        exported.exportScope.forEach(export.addToExportScope);
      }
    }

    while (true) {
      var hasChanges = false;
      for (var exported in both) {
        for (var export in exported.exporters) {
          exported.exportScope.forEach((name, member) {
            if (export.addToExportScope(name, member)) {
              hasChanges = true;
            }
          });
        }
      }
      if (!hasChanges) break;
    }

    for (var library in builders.values) {
      library.storeExportScope();
    }

    for (var library in builders.values) {
      library.buildElement();
    }
  }

  void _createLinkingBundle() {
    var linkingLibraries = <LinkedNodeLibraryBuilder>[];
    for (var builder in builders.values) {
      linkingLibraries.add(builder.node);

      for (var unitContext in builder.context.units) {
        var unit = unitContext.unit;

        var writer = AstBinaryWriter(linkingBundleContext);
        var unitLinkedNode = writer.writeNode(unit);
        builder.node.units.add(
          LinkedNodeUnitBuilder(
            isSynthetic: unitContext.isSynthetic,
            uriStr: unitContext.uriStr,
            lineStarts: unit.lineInfo.lineStarts,
            node: unitLinkedNode,
          ),
        );
      }
    }
    linkingBundle = LinkedNodeBundleBuilder(
      references: linkingBundleContext.referencesBuilder,
      libraries: linkingLibraries,
    );
  }

  void _createLoadLibraryFunctions() {
    for (var library in builders.values) {
      library.element.createLoadLibraryFunction(typeProvider);
    }
  }

  void _createTypeSystem() {
    if (typeProvider != null) {
      inheritance = InheritanceManager2(typeSystem);
      return;
    }

    var coreLib = elementFactory.libraryOfUri('dart:core');
    var asyncLib = elementFactory.libraryOfUri('dart:async');

    analysisContext.typeProvider = SummaryTypeProvider()
      ..initializeCore(coreLib)
      ..initializeAsync(asyncLib);

    inheritance = InheritanceManager2(typeSystem);
  }

  void _performTopLevelInference() {
    TopLevelInference(this).infer();
  }

  void _resolveConstantInitializers() {
    ConstantInitializersResolver(this).perform();
  }

  void _resolveConstructors() {
    for (var library in builders.values) {
      library.resolveConstructors();
    }
  }

  void _resolveDefaultValues() {
    for (var library in builders.values) {
      library.resolveDefaultValues();
    }
  }

  void _resolveMetadata() {
    for (var library in builders.values) {
      library.resolveMetadata();
    }
  }

  void _resolveTypes() {
    var nodesToBuildType = NodesToBuildType();
    for (var library in builders.values) {
      library.resolveTypes(nodesToBuildType);
    }
    computeSimplyBounded(bundleContext, builders.values);
    TypesBuilder(typeSystem).build(nodesToBuildType);
  }

  void _resolveUriDirectives() {
    for (var library in builders.values) {
      library.resolveUriDirectives();
    }
  }
}

class LinkInputLibrary {
  final Source source;
  final List<LinkInputUnit> units;

  LinkInputLibrary(this.source, this.units);
}

class LinkInputUnit {
  final Source source;
  final bool isSynthetic;
  final CompilationUnit unit;

  LinkInputUnit(this.source, this.isSynthetic, this.unit);
}

class LinkResult {
  final LinkedNodeBundleBuilder bundle;

  LinkResult(this.bundle);
}
