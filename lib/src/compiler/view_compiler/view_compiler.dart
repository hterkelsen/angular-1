import "package:angular2/src/core/di.dart" show Injectable;

import "../compile_metadata.dart"
    show CompileDirectiveMetadata, CompilePipeMetadata;
import "../config.dart" show CompilerConfig;
import "../identifiers.dart";
import "../output/output_ast.dart" as o;
import "../template_ast.dart" show TemplateAst, templateVisitAll;
import "../style_compiler.dart" show StylesCompileResult;
import "compile_element.dart" show CompileElement;
import "compile_view.dart" show CompileView;
import "view_binder.dart" show bindView;
import "view_builder.dart";

class ViewCompileResult {
  List<o.Statement> statements;
  String viewFactoryVar;
  List<ViewCompileDependency> dependencies;
  ViewCompileResult(this.statements, this.viewFactoryVar, this.dependencies);
}

@Injectable()
class ViewCompiler {
  CompilerConfig _genConfig;
  ViewCompiler(this._genConfig);

  ViewCompileResult compileComponent(
      CompileDirectiveMetadata component,
      List<TemplateAst> template,
      StylesCompileResult stylesCompileResult,
      o.Expression styles,
      List<CompilePipeMetadata> pipes) {
    var statements = <o.Statement>[];
    var dependencies = <ViewCompileDependency>[];
    var view = new CompileView(component, this._genConfig, pipes, styles, 0,
        new CompileElement.root(), []);
    buildView(view, template, stylesCompileResult, dependencies);
    // Need to separate binding from creation to be able to refer to
    // variables that have been declared after usage.
    bindView(view, template);
    finishView(view, statements);
    return new ViewCompileResult(
        statements, view.viewFactory.name, dependencies);
  }

  /// Builds the view and returns number of nested views generated.
  int buildView(
      CompileView view,
      List<TemplateAst> template,
      StylesCompileResult stylesCompileResult,
      List<ViewCompileDependency> targetDependencies) {
    var builderVisitor =
        new ViewBuilderVisitor(view, targetDependencies, stylesCompileResult);
    templateVisitAll(
        builderVisitor,
        template,
        view.declarationElement.hasRenderNode
            ? view.declarationElement.parent
            : view.declarationElement);
    return builderVisitor.nestedViewCount;
  }

  /// Creates top level statements for main and nested views generated by
  /// buildView.
  void finishView(CompileView view, List<o.Statement> targetStatements) {
    view.afterNodes();
    createViewTopLevelStmts(view, targetStatements);
    int nodeCount = view.nodes.length;
    var nodes = view.nodes;
    for (int i = 0; i < nodeCount; i++) {
      var node = nodes[i];
      if (node is CompileElement && node.embeddedView != null) {
        finishView(node.embeddedView, targetStatements);
      }
    }
  }

  void createViewTopLevelStmts(
      CompileView view, List<o.Statement> targetStatements) {
    o.Expression nodeDebugInfosVar =
        createStaticNodeDebugInfos(view, targetStatements);

    // Create renderType global to hold RenderComponentType instance.
    String renderTypeVarName = 'renderType_${view.component.type.name}';
    o.ReadVarExpr renderCompTypeVar = o.variable(renderTypeVarName);
    // If we are compiling root view, create a render type for the component.
    // Example: RenderComponentType renderType_MaterialButtonComponent;
    if (identical(view.viewIndex, 0)) {
      targetStatements.add(new o.DeclareVarStmt(renderTypeVarName, null,
          o.importType(Identifiers.RenderComponentType)));
    }
    var viewClass = createViewClass(view, renderCompTypeVar, nodeDebugInfosVar);
    targetStatements.add(viewClass);
    targetStatements.add(createViewFactory(view, viewClass, renderCompTypeVar));
  }

  /// Create top level node debug info.
  /// Example:
  /// const List<StaticNodeDebugInfo> nodeDebugInfos_MyAppComponent0 = const [
  ///     const StaticNodeDebugInfo(const [],null,const <String, dynamic>{}),
  ///     const StaticNodeDebugInfo(const [],null,const <String, dynamic>{}),
  ///     const StaticNodeDebugInfo(const [
  ///       import1.AcxDarkTheme,
  ///       import2.MaterialButtonComponent,
  ///       import3.ButtonDirective
  ///     ]
  ///     ,import2.MaterialButtonComponent,const <String, dynamic>{}),
  /// const StaticNodeDebugInfo(const [],null,const <String, dynamic>{}),
  o.Expression createStaticNodeDebugInfos(
      CompileView view, List<o.Statement> targetStatements) {
    o.Expression nodeDebugInfosVar = o.NULL_EXPR;
    if (view.genConfig.genDebugInfo) {
      nodeDebugInfosVar = o.variable(
          'nodeDebugInfos_${view.component.type.name}${view.viewIndex}');
      targetStatements.add(((nodeDebugInfosVar as o.ReadVarExpr))
          .set(o.literalArr(
              view.nodes.map(createStaticNodeDebugInfo).toList(),
              new o.ArrayType(
                  new o.ExternalType(Identifiers.StaticNodeDebugInfo),
                  [o.TypeModifier.Const])))
          .toDeclStmt(null, [o.StmtModifier.Final]));
    }
    return nodeDebugInfosVar;
  }
}
