// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/flow_analysis/flow_analysis.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'package:analyzer/src/dart/resolver/extension_member_resolver.dart';
import 'package:analyzer/src/dart/resolver/flow_analysis_visitor.dart';
import 'package:analyzer/src/dart/resolver/resolution_result.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';

/// Helper for resolving properties (getters, setters, or methods).
class TypePropertyResolver {
  final ResolverVisitor _resolver;
  final LibraryElement _definingLibrary;
  final bool _isNonNullableByDefault;
  final TypeSystemImpl _typeSystem;
  final TypeProviderImpl _typeProvider;
  final ExtensionMemberResolver _extensionResolver;

  late Expression? _receiver;
  late SyntacticEntity _nameErrorEntity;
  late String _name;

  bool _needsGetterError = false;
  bool _reportedGetterError = false;
  ExecutableElement? _getterRequested;
  ExecutableElement? _getterRecovery;

  bool _needsSetterError = false;
  bool _reportedSetterError = false;
  ExecutableElement? _setterRequested;
  ExecutableElement? _setterRecovery;

  TypePropertyResolver(this._resolver)
      : _definingLibrary = _resolver.definingLibrary,
        _isNonNullableByDefault = _resolver.typeSystem.isNonNullableByDefault,
        _typeSystem = _resolver.typeSystem,
        _typeProvider = _resolver.typeProvider,
        _extensionResolver = _resolver.extensionResolver;

  bool get _hasGetterOrSetter {
    return _getterRequested != null || _setterRequested != null;
  }

  /// Look up the property with the given [name] in the [receiverType].
  ///
  /// The [receiver] might be `null`, used to identify `super`.
  ///
  /// The [receiverErrorNode] is the node to report nullable dereference,
  /// if the [receiverType] is potentially nullable.
  ///
  /// The [nameErrorEntity] is used to report the ambiguous extension issue.
  ResolutionResult resolve({
    required Expression? receiver,
    required DartType receiverType,
    required String name,
    required AstNode receiverErrorNode,
    required SyntacticEntity nameErrorEntity,
  }) {
    _receiver = receiver;
    _name = name;
    _nameErrorEntity = nameErrorEntity;
    _resetResult();

    receiverType = _resolveTypeParameter(receiverType, ifLegacy: true);

    if (_typeSystem.isDynamicBounded(receiverType)) {
      _lookupInterfaceType(_typeProvider.objectType);
      _needsGetterError = false;
      _needsSetterError = false;
      return _toResult();
    }

    if (_isNonNullableByDefault &&
        _typeSystem.isPotentiallyNullable(receiverType)) {
      _lookupInterfaceType(_typeProvider.objectType);
      if (_hasGetterOrSetter) {
        return _toResult();
      }

      _lookupExtension(receiverType);
      if (_hasGetterOrSetter) {
        return _toResult();
      }

      var parentExpression = (receiver ?? receiverErrorNode).parent;
      CompileTimeErrorCode errorCode;
      if (parentExpression == null) {
        errorCode = CompileTimeErrorCode.UNCHECKED_INVOCATION_OF_NULLABLE_VALUE;
      } else {
        if (parentExpression is CascadeExpression) {
          parentExpression = parentExpression.cascadeSections.first;
        }
        if (parentExpression is BinaryExpression) {
          errorCode = CompileTimeErrorCode
              .UNCHECKED_OPERATOR_INVOCATION_OF_NULLABLE_VALUE;
        } else if (parentExpression is MethodInvocation ||
            parentExpression is MethodReferenceExpression) {
          errorCode = CompileTimeErrorCode
              .UNCHECKED_METHOD_INVOCATION_OF_NULLABLE_VALUE;
        } else if (parentExpression is FunctionExpressionInvocation) {
          errorCode =
              CompileTimeErrorCode.UNCHECKED_INVOCATION_OF_NULLABLE_VALUE;
        } else {
          errorCode =
              CompileTimeErrorCode.UNCHECKED_PROPERTY_ACCESS_OF_NULLABLE_VALUE;
        }
      }

      var whyNotPromoted = receiver == null
          ? null
          : _resolver.flowAnalysis?.flow?.whyNotPromoted(receiver);
      List<DiagnosticMessage> messages = [];
      if (whyNotPromoted != null) {
        for (var entry in whyNotPromoted.entries) {
          var whyNotPromotedVisitor = _WhyNotPromotedVisitor(
              _resolver.source, _resolver.flowAnalysis!.dataForTesting);
          if (_typeSystem.isPotentiallyNullable(entry.key)) continue;
          if (_resolver.flowAnalysis!.dataForTesting != null) {
            _resolver.flowAnalysis!.dataForTesting!
                .nonPromotionReasons[nameErrorEntity] = entry.value.shortName;
          }
          var message = entry.value.accept(whyNotPromotedVisitor);
          if (message != null) {
            messages = [message];
          }
          break;
        }
      }

      _resolver.nullableDereferenceVerifier.report(
          receiverErrorNode, receiverType,
          errorCode: errorCode, arguments: [name], messages: messages);
      _reportedGetterError = true;
      _reportedSetterError = true;

      // Recovery, get some resolution.
      receiverType = _resolveTypeParameter(receiverType, ifNullSafe: true);
      if (receiverType is InterfaceType) {
        _lookupInterfaceType(receiverType);
      }

      return _toResult();
    } else {
      var receiverTypeResolved =
          _resolveTypeParameter(receiverType, ifNullSafe: true);

      if (receiverTypeResolved is InterfaceType) {
        _lookupInterfaceType(receiverTypeResolved);
        if (_hasGetterOrSetter) {
          return _toResult();
        }
        if (receiverTypeResolved.isDartCoreFunction && _name == 'call') {
          _needsGetterError = false;
          _needsSetterError = false;
          return _toResult();
        }
      }

      if (receiverTypeResolved is FunctionType && _name == 'call') {
        return _toResult();
      }

      if (receiverTypeResolved is NeverType) {
        _lookupInterfaceType(_typeProvider.objectType);
        _needsGetterError = false;
        _needsSetterError = false;
        return _toResult();
      }

      _lookupExtension(receiverType);
      if (_hasGetterOrSetter) {
        return _toResult();
      }

      _lookupInterfaceType(_typeProvider.objectType);

      return _toResult();
    }
  }

  void _lookupExtension(DartType type) {
    var result =
        _extensionResolver.findExtension(type, _nameErrorEntity, _name);
    _reportedGetterError = result.isAmbiguous;
    _reportedSetterError = result.isAmbiguous;

    if (result.getter != null) {
      _needsGetterError = false;
      _getterRequested = result.getter;
    }

    if (result.setter != null) {
      _needsSetterError = false;
      _setterRequested = result.setter;
    }
  }

  void _lookupInterfaceType(InterfaceType type) {
    var isSuper = _receiver is SuperExpression;

    var getterName = Name(_definingLibrary.source.uri, _name);
    _getterRequested =
        _resolver.inheritance.getMember(type, getterName, forSuper: isSuper);
    _needsGetterError = _getterRequested == null;

    if (_getterRequested == null) {
      var classElement = type.element as AbstractClassElementImpl;
      _getterRecovery ??=
          classElement.lookupStaticGetter(_name, _definingLibrary) ??
              classElement.lookupStaticMethod(_name, _definingLibrary);
      _needsGetterError = _getterRecovery == null;
    }

    var setterName = Name(_definingLibrary.source.uri, '$_name=');
    _setterRequested =
        _resolver.inheritance.getMember(type, setterName, forSuper: isSuper);
    _needsSetterError = _setterRequested == null;

    if (_setterRequested == null) {
      var classElement = type.element as AbstractClassElementImpl;
      _setterRecovery ??=
          classElement.lookupStaticSetter(_name, _definingLibrary);
      _needsSetterError = _setterRecovery == null;
    }
  }

  void _resetResult() {
    _needsGetterError = false;
    _reportedGetterError = false;
    _getterRequested = null;
    _getterRecovery = null;

    _needsSetterError = false;
    _reportedSetterError = false;
    _setterRequested = null;
    _setterRecovery = null;
  }

  /// If the given [type] is a type parameter, replace it with its bound.
  /// Otherwise, return the original type.
  ///
  /// See https://github.com/dart-lang/language/issues/1182
  /// There was a bug in the analyzer (and CFE) - we were always resolving
  /// types to bounds before searching for a property.  But  extensions should
  /// be applied to original types.  Fixing this would be a breaking change,
  /// so we fix it together with null safety.
  DartType _resolveTypeParameter(
    DartType type, {
    bool ifLegacy = false,
    bool ifNullSafe = false,
  }) {
    if (_typeSystem.isNonNullableByDefault ? ifNullSafe : ifLegacy) {
      return type.resolveToBound(_typeProvider.objectType);
    } else {
      return type;
    }
  }

  ResolutionResult _toResult() {
    _getterRequested = _resolver.toLegacyElement(_getterRequested);
    _getterRecovery = _resolver.toLegacyElement(_getterRecovery);

    _setterRequested = _resolver.toLegacyElement(_setterRequested);
    _setterRecovery = _resolver.toLegacyElement(_setterRecovery);

    var getter = _getterRequested ?? _getterRecovery;
    var setter = _setterRequested ?? _setterRecovery;

    return ResolutionResult(
      getter: getter,
      // Parser recovery resulting in an empty property name should not be
      // reported as an undefined getter.
      needsGetterError:
          _needsGetterError && _name.isNotEmpty && !_reportedGetterError,
      setter: setter,
      needsSetterError: _needsSetterError && !_reportedSetterError,
    );
  }
}

class _WhyNotPromotedVisitor
    implements
        NonPromotionReasonVisitor<DiagnosticMessage?, AstNode, Expression,
            PromotableElement> {
  final Source source;

  final FlowAnalysisDataForTesting? _dataForTesting;

  _WhyNotPromotedVisitor(this.source, this._dataForTesting);

  @override
  DiagnosticMessage? visitDemoteViaExplicitWrite(
      DemoteViaExplicitWrite<PromotableElement, Expression> reason) {
    var writeExpression = reason.writeExpression;
    if (_dataForTesting != null) {
      _dataForTesting!.nonPromotionReasonTargets[writeExpression] =
          reason.shortName;
    }
    var variableName = reason.variable.name;
    if (variableName == null) return null;
    return _contextMessageForWrite(variableName, writeExpression);
  }

  @override
  DiagnosticMessage? visitDemoteViaForEachVariableWrite(
      DemoteViaForEachVariableWrite<PromotableElement, AstNode> reason) {
    var node = reason.node;
    var variableName = reason.variable.name;
    if (variableName == null) return null;
    ForLoopParts parts;
    if (node is ForStatement) {
      parts = node.forLoopParts;
    } else if (node is ForElement) {
      parts = node.forLoopParts;
    } else {
      assert(false, 'Unexpected node type');
      return null;
    }
    if (parts is ForEachPartsWithIdentifier) {
      var identifier = parts.identifier;
      if (_dataForTesting != null) {
        _dataForTesting!.nonPromotionReasonTargets[identifier] =
            reason.shortName;
      }
      return _contextMessageForWrite(variableName, identifier);
    } else {
      assert(false, 'Unexpected parts type');
      return null;
    }
  }

  @override
  DiagnosticMessage? visitFieldNotPromoted(FieldNotPromoted reason) {
    // TODO(paulberry): how to report this?
    return null;
  }

  DiagnosticMessageImpl _contextMessageForWrite(
      String variableName, Expression writeExpression) {
    return DiagnosticMessageImpl(
        filePath: source.fullName,
        message:
            "Variable '$variableName' could be null due to a write occurring here.",
        offset: writeExpression.offset,
        length: writeExpression.length);
  }
}
