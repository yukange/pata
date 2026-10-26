import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

// Execute production component callbacks with controlled services, refs, and state setters.
export function componentCallbacks(file: URL) {
  const source = ts.createSourceFile(file.pathname, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const expressions = new Map<string, ts.Node>();
  function visit(node: ts.Node) {
    if (ts.isFunctionDeclaration(node) && node.name) expressions.set(node.name.text, node);
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) {
      const init = node.initializer;
      expressions.set(node.name.text, ts.isCallExpression(init) && init.expression.getText(source) === 'useCallback' ? init.arguments[0] : init);
    }
    if (ts.isCallExpression(node) && node.expression.getText(source) === 'Events.On' && ts.isStringLiteral(node.arguments[0])) {
      expressions.set(`event:${node.arguments[0].text}`, node.arguments[1]);
    }
    ts.forEachChild(node, visit);
  }
  visit(source);
  return (name: string, context: Record<string, unknown> = {}) => {
    const expression = expressions.get(name);
    assert.ok(expression, `missing ${name} in ${file.pathname}`);
    const code = ts.transpileModule(`(${expression.getText(source)})`, {
      fileName: 'callback.tsx',
      compilerOptions: { target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.React },
    }).outputText;
    return vm.runInNewContext(code, context);
  };
}
