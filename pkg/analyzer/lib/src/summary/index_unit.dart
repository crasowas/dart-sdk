// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/idl.dart';

/**
 * Object that gathers information about the whole package index and then uses
 * it to assemble a new [PackageIndexBuilder].  Call [index] on each compilation
 * unit to be indexed, then call [assemble] to retrieve the complete index for
 * the package.
 */
class PackageIndexAssembler {
  /**
   * Map associating referenced elements with their [_ElementInfo]s.
   */
  final Map<Element, _ElementInfo> _elementMap = <Element, _ElementInfo>{};

  /**
   * Map associating [CompilationUnitElement]s with their identifiers, which
   * are indices into [_unitLibraryUris] and [_unitUnitUris].
   */
  final Map<CompilationUnitElement, int> _unitMap =
      <CompilationUnitElement, int>{};

  /**
   * Each item of this list corresponds to the library URI of a unique
   * [CompilationUnitElement].  It is an index into [_strings].
   */
  final List<int> _unitLibraryUris = <int>[];

  /**
   * Each item of this list corresponds to the unit URI of a unique
   * [CompilationUnitElement].  It is an index into [_strings].
   */
  final List<int> _unitUnitUris = <int>[];

  /**
   * Map associating strings with their identifiers, which are indices
   * into [_strings].
   */
  final Map<String, int> _stringMap = <String, int>{};

  /**
   * List of unique strings used in this index.
   */
  final List<String> _strings = <String>[];

  /**
   * List of information about each unit indexed in this index.
   */
  final List<_UnitIndexAssembler> _units = <_UnitIndexAssembler>[];

  /**
   * Assemble a new [PackageIndexBuilder] using the information gathered by
   * [index].
   */
  PackageIndexBuilder assemble() {
    List<_ElementInfo> elementInfoList = _elementMap.values.toList();
    elementInfoList.sort((a, b) {
      return a.offset - b.offset;
    });
    for (int i = 0; i < elementInfoList.length; i++) {
      elementInfoList[i].id = i;
    }
    return new PackageIndexBuilder(
        unitLibraryUris: _unitLibraryUris,
        unitUnitUris: _unitUnitUris,
        elementUnits: elementInfoList.map((e) => e.unitId).toList(),
        elementOffsets: elementInfoList.map((e) => e.offset).toList(),
        elementKinds: elementInfoList.map((e) => e.kind).toList(),
        strings: _strings,
        units: _units.map((unit) => unit.assemble()).toList());
  }

  /**
   * Index the given fully resolved [unit].
   */
  void index(CompilationUnit unit) {
    int unitId = _getUnitId(unit.element);
    _UnitIndexAssembler assembler = new _UnitIndexAssembler(this, unitId);
    _units.add(assembler);
    unit.accept(new _IndexContributor(assembler));
  }

  /**
   * Return the unique [_ElementInfo] corresponding the [element].  The field
   * [_ElementInfo.id] is filled by [assemble] during final sorting.
   */
  _ElementInfo _getElementInfo(Element element) {
    if (element is Member) {
      element = (element as Member).baseElement;
    }
    return _elementMap.putIfAbsent(element, () {
      CompilationUnitElement unitElement = getUnitElement(element);
      int unitId = _getUnitId(unitElement);
      int offset = element.nameOffset;
      if (element is LibraryElement || element is CompilationUnitElement) {
        offset = 0;
      }
      IndexSyntheticElementKind kind = getIndexElementKind(element);
      return new _ElementInfo(element, unitId, offset, kind);
    });
  }

  /**
   * Add information about [str] to [_strings] if necessary, and return the
   * location in this array representing [str].
   */
  int _getStringId(String str) {
    return _stringMap.putIfAbsent(str, () {
      int id = _strings.length;
      _strings.add(str);
      return id;
    });
  }

  /**
   * Add information about [unitElement] to [_unitUnitUris] and
   * [_unitLibraryUris] if necessary, and return the location in those
   * arrays representing [unitElement].
   */
  int _getUnitId(CompilationUnitElement unitElement) {
    return _unitMap.putIfAbsent(unitElement, () {
      assert(_unitLibraryUris.length == _unitUnitUris.length);
      int id = _unitUnitUris.length;
      _unitLibraryUris.add(_getUriId(unitElement.library.source.uri));
      _unitUnitUris.add(_getUriId(unitElement.source.uri));
      return id;
    });
  }

  /**
   * Return the identifier corresponding to [uri].
   */
  int _getUriId(Uri uri) {
    String str = uri.toString();
    return _getStringId(str);
  }

  /**
   * Return the kind of the given [element].
   */
  static IndexSyntheticElementKind getIndexElementKind(Element element) {
    if (element.isSynthetic) {
      if (element is ConstructorElement) {
        return IndexSyntheticElementKind.constructor;
      }
      if (element is PropertyAccessorElement) {
        return element.isGetter
            ? IndexSyntheticElementKind.getter
            : IndexSyntheticElementKind.setter;
      }
    }
    return IndexSyntheticElementKind.notSynthetic;
  }

  /**
   * Return the [CompilationUnitElement] that should be used for [element].
   * Throw [StateError] if the [element] is not linked into a unit.
   */
  static CompilationUnitElement getUnitElement(Element element) {
    for (Element e = element; e != null; e = e.enclosingElement) {
      if (e is CompilationUnitElement) {
        return e;
      }
      if (e is LibraryElement) {
        return e.definingCompilationUnit;
      }
    }
    throw new StateError(element.toString());
  }
}

/**
 * Information about a single defined name.  Any [_DefinedNameInfo] is always
 * part of a [_UnitIndexAssembler], so [offset] should be understood within the
 * context of the compilation unit pointed to by the [_UnitIndexAssembler].
 */
class _DefinedNameInfo {
  final int nameId;
  final IndexNameKind kind;
  final int offset;

  _DefinedNameInfo(this.nameId, this.kind, this.offset);
}

/**
 * Information about an element referenced in index.
 */
class _ElementInfo {
  /**
   * TODO(scheglov) remove after fixing build flakiness on bots
   */
  final Element element;

  /**
   * The identifier of the [CompilationUnitElement] containing this element.
   */
  final int unitId;

  /**
   * The name offset of the element.
   */
  final int offset;

  /**
   * The kind of the element.
   */
  final IndexSyntheticElementKind kind;

  /**
   * The unique id of the element.  It is set after indexing of the whole
   * package is done and we are assembling the full package index.
   */
  int id;

  _ElementInfo(this.element, this.unitId, this.offset, this.kind);
}

/**
 * Visits a resolved AST and adds relationships into [_UnitIndexAssembler].
 */
class _IndexContributor extends GeneralizingAstVisitor {
  final _UnitIndexAssembler assembler;

  _IndexContributor(this.assembler);

  /**
   * Record definition of the given [element].
   */
  void recordDefinedElement(Element element) {
    if (element != null) {
      String name = element.displayName;
      int offset = element.nameOffset;
      Element enclosing = element.enclosingElement;
      if (enclosing is CompilationUnitElement) {
        assembler.defineName(name, IndexNameKind.topLevel, offset);
      } else if (enclosing is ClassElement) {
        assembler.defineName(name, IndexNameKind.classMember, offset);
      }
    }
  }

  /**
   * Record reference to the given operator [Element] and name.
   */
  void recordOperatorReference(Token operator, Element element) {
    recordRelationToken(element, IndexRelationKind.IS_INVOKED_BY, operator);
    // TODO(scheglov) do we need this?
//    // prepare location
//    LocationImpl location = _createLocationForToken(operator, element != null);
//    // record name reference
//    {
//      String name = operator.lexeme;
//      if (name == "++") {
//        name = "+";
//      }
//      if (name == "--") {
//        name = "-";
//      }
//      if (StringUtilities.endsWithChar(name, 0x3D) && name != "==") {
//        name = name.substring(0, name.length - 1);
//      }
//      IndexableName indexableName = new IndexableName(name);
//      recordRelationshipIndexable(
//          indexableName, IndexConstants.IS_INVOKED_BY, location);
//    }
//    // record element reference
//    if (element != null) {
//      recordRelationshipElement(
//          element, IndexConstants.IS_INVOKED_BY, location);
//    }
  }

  /**
   * Record that [element] has a relation of the given [kind] at the location
   * of the given [node].
   */
  void recordRelation(Element element, IndexRelationKind kind, AstNode node) {
    if (element != null && node != null) {
      recordRelationOffset(element, kind, node.offset, node.length);
    }
  }

  /**
   * Record that [element] has a relation of the given [kind] at the given
   * [offset] and [length].
   */
  void recordRelationOffset(
      Element element, IndexRelationKind kind, int offset, int length) {
    // Ignore elements that can't be referenced outside of the unit.
    if (element == null ||
        element is FunctionElement &&
            element.enclosingElement is ExecutableElement ||
        element is LabelElement ||
        element is LocalVariableElement ||
        element is ParameterElement &&
            element.parameterKind != ParameterKind.NAMED ||
        element is PrefixElement ||
        element is TypeParameterElement) {
      return;
    }
    // Add the relation.
    assembler.addRelation(element, kind, offset, length);
  }

  /**
   * Record that [element] has a relation of the given [kind] at the location
   * of the given [token].
   */
  void recordRelationToken(
      Element element, IndexRelationKind kind, Token token) {
    if (element != null && token != null) {
      recordRelationOffset(element, kind, token.offset, token.length);
    }
  }

  /**
   * Record a relation between a super [typeName] and its [Element].
   */
  void recordSuperType(TypeName typeName, IndexRelationKind kind) {
    Identifier name = typeName?.name;
    if (name != null) {
      recordRelation(name.staticElement, kind, name);
      typeName.typeArguments?.accept(this);
    }
  }

  void recordUriReference(Element element, UriBasedDirective directive) {
    recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, directive.uri);
  }

  @override
  visitAssignmentExpression(AssignmentExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitAssignmentExpression(node);
  }

  @override
  visitBinaryExpression(BinaryExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitBinaryExpression(node);
  }

  @override
  visitClassDeclaration(ClassDeclaration node) {
    if (node.extendsClause == null) {
      ClassElement objectElement = node.element.supertype?.element;
      recordRelationOffset(
          objectElement, IndexRelationKind.IS_EXTENDED_BY, node.name.offset, 0);
    }
    super.visitClassDeclaration(node);
  }

  @override
  visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    SimpleIdentifier fieldName = node.fieldName;
    if (fieldName != null) {
      Element element = fieldName.staticElement;
      recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, fieldName);
    }
    node.expression?.accept(this);
  }

  @override
  visitConstructorName(ConstructorName node) {
    ConstructorElement element = node.staticElement;
    // in 'class B = A;' actually A constructors are invoked
    // TODO(scheglov) add support for multiple levels of redirection
    // TODO(scheglov) test for a loop of redirection
    if (element != null &&
        element.isSynthetic &&
        element.redirectedConstructor != null) {
      element = element.redirectedConstructor;
    }
    // record relation
    if (node.name != null) {
      int offset = node.period.offset;
      int length = node.name.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.type.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitConstructorName(node);
  }

  @override
  visitExportDirective(ExportDirective node) {
    ExportElement element = node.element;
    recordUriReference(element?.exportedLibrary, node);
    super.visitExportDirective(node);
  }

  @override
  visitExtendsClause(ExtendsClause node) {
    recordSuperType(node.superclass, IndexRelationKind.IS_EXTENDED_BY);
  }

  @override
  visitImplementsClause(ImplementsClause node) {
    for (TypeName typeName in node.interfaces) {
      recordSuperType(typeName, IndexRelationKind.IS_IMPLEMENTED_BY);
    }
  }

  @override
  visitImportDirective(ImportDirective node) {
    ImportElement element = node.element;
    recordUriReference(element?.importedLibrary, node);
    super.visitImportDirective(node);
  }

  @override
  visitIndexExpression(IndexExpression node) {
    MethodElement element = node.bestElement;
    if (element is MethodElement) {
      Token operator = node.leftBracket;
      recordRelationToken(element, IndexRelationKind.IS_INVOKED_BY, operator);
    }
    super.visitIndexExpression(node);
  }

  @override
  visitMethodInvocation(MethodInvocation node) {
    SimpleIdentifier name = node.methodName;
    // TODO(scheglov) do we need this?
//    LocationImpl location = _createLocationForNode(name);
//    // name invocation
//    recordRelationshipIndexable(
//        new IndexableName(name.name), IndexConstants.IS_INVOKED_BY, location);
    // element invocation
    Element element = name.bestElement;
    if (element is MethodElement ||
        element is PropertyAccessorElement ||
        element is FunctionElement ||
        element is VariableElement) {
      IndexRelationKind kind = node.realTarget != null
          ? IndexRelationKind.IS_INVOKED_QUALIFIED_BY
          : IndexRelationKind.IS_INVOKED_BY;
      recordRelation(element, kind, name);
    } else if (element is ClassElement) {
      recordRelation(element, IndexRelationKind.IS_REFERENCED_BY, name);
    }
    node.target?.accept(this);
    node.argumentList?.accept(this);
  }

  @override
  visitPartDirective(PartDirective node) {
    Element element = node.element;
    recordUriReference(element, node);
    super.visitPartDirective(node);
  }

  @override
  visitPostfixExpression(PostfixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitPostfixExpression(node);
  }

  @override
  visitPrefixExpression(PrefixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    super.visitPrefixExpression(node);
  }

  @override
  visitRedirectingConstructorInvocation(RedirectingConstructorInvocation node) {
    ConstructorElement element = node.staticElement;
    if (node.constructorName != null) {
      int offset = node.period.offset;
      int length = node.constructorName.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.thisKeyword.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  visitSimpleIdentifier(SimpleIdentifier node) {
    Element element = node.bestElement;
    // TODO(scheglov) do we need this?
//    IndexableName indexableName = new IndexableName(node.name);
//    LocationImpl location = _createLocationForNode(node);
//    if (location == null) {
//      return;
//    }
    // name in declaration
    if (node.inDeclarationContext()) {
      recordDefinedElement(element);
      return;
    }
    // this.field parameter
    if (element is FieldFormalParameterElement) {
      recordRelation(element.field, IndexRelationKind.IS_REFERENCED_BY, node);
      return;
    }
    // record specific relations
    IndexRelationKind kind = node.isQualified
        ? IndexRelationKind.IS_REFERENCED_QUALIFIED_BY
        : IndexRelationKind.IS_REFERENCED_BY;
    recordRelation(element, kind, node);
  }

  @override
  visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    ConstructorElement element = node.staticElement;
    if (node.constructorName != null) {
      int offset = node.period.offset;
      int length = node.constructorName.end - offset;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, length);
    } else {
      int offset = node.superKeyword.end;
      recordRelationOffset(
          element, IndexRelationKind.IS_REFERENCED_BY, offset, 0);
    }
    super.visitSuperConstructorInvocation(node);
  }

  @override
  visitTypeName(TypeName node) {
    AstNode parent = node.parent;
    if (parent is ClassTypeAlias && parent.superclass == node) {
      recordSuperType(node, IndexRelationKind.IS_EXTENDED_BY);
    } else {
      super.visitTypeName(node);
    }
  }

  @override
  visitWithClause(WithClause node) {
    for (TypeName typeName in node.mixinTypes) {
      recordSuperType(typeName, IndexRelationKind.IS_MIXED_IN_BY);
    }
  }
}

/**
 * Information about a single relation.  Any [_RelationInfo] is always part
 * of a [_UnitIndexAssembler], so [offset] and [length] should be understood
 * within the context of the compilation unit pointed to by the
 * [_UnitIndexAssembler].
 */
class _RelationInfo {
  final _ElementInfo elementInfo;
  final IndexRelationKind kind;
  final int offset;
  final int length;

  _RelationInfo(this.elementInfo, this.kind, this.offset, this.length);
}

/**
 * Assembler of a single [CompilationUnit] index.  The intended usage sequence:
 *
 *  - Call [defineName] for name defined in the compilation unit.
 *  - Call [addRelation] for each relation found in the compilation unit.
 *  - Assign ids to all the [_ElementInfo] objects reachable from [relations].
 *  - Call [assemble] to produce the final unit index.
 */
class _UnitIndexAssembler {
  final PackageIndexAssembler pkg;
  final int unitId;
  final List<_DefinedNameInfo> definedNames = <_DefinedNameInfo>[];
  final List<_RelationInfo> relations = <_RelationInfo>[];

  _UnitIndexAssembler(this.pkg, this.unitId);

  void addRelation(
      Element element, IndexRelationKind kind, int offset, int length) {
    try {
      _ElementInfo elementInfo = pkg._getElementInfo(element);
      relations.add(new _RelationInfo(elementInfo, kind, offset, length));
    } on StateError {}
  }

  /**
   * Assemble a new [UnitIndexBuilder] using the information gathered
   * by [addRelation] and [defineName].
   */
  UnitIndexBuilder assemble() {
    relations.sort((a, b) {
      if (a.elementInfo.id == null) {
        throw new StateError('No id for ${a.elementInfo.element}, '
            'location= ${a.elementInfo.element?.location}');
      }
      return a.elementInfo.id - b.elementInfo.id;
    });
    definedNames.sort((a, b) {
      return a.nameId - b.nameId;
    });
    return new UnitIndexBuilder(
        unit: unitId,
        definedNames: definedNames.map((n) => n.nameId).toList(),
        definedNameKinds: definedNames.map((n) => n.kind).toList(),
        definedNameOffsets: definedNames.map((n) => n.offset).toList(),
        usedElements: relations.map((r) => r.elementInfo.id).toList(),
        usedElementKinds: relations.map((r) => r.kind).toList(),
        usedElementOffsets: relations.map((r) => r.offset).toList(),
        usedElementLengths: relations.map((r) => r.length).toList());
  }

  void defineName(String name, IndexNameKind kind, int offset) {
    int nameId = pkg._getStringId(name);
    definedNames.add(new _DefinedNameInfo(nameId, kind, offset));
  }
}
