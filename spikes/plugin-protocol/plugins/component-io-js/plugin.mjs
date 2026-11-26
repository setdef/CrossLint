// JavaScript plugin: a component's inputs and outputs, inherited ones included,
// must all appear in its interface file. The reading follows approach B of
// spikes/ts-from-ruby: the TypeScript compiler API, from the project's own `typescript`.
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { join } from 'node:path';

class PluginError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function loadTypeScript(root) {
  try { return createRequire(join(root, 'package.json'))('typescript'); }
  catch { throw new PluginError('dependency-missing', `the project at ${root} has no installed "typescript"`); }
}

function check({ root, items }) {
  const ts = loadTypeScript(root);
  const config = ts.getParsedCommandLineOfConfigFile(join(root, 'tsconfig.json'), {}, {
    ...ts.sys, onUnRecoverableConfigFileDiagnostic: (d) => { throw new PluginError('bad-project', ts.flattenDiagnosticMessageText(d.messageText, '\n')); },
  });
  const abs = (p) => join(root, p);
  const program = ts.createProgram({ rootNames: [...config.fileNames, ...items.flatMap((i) => [abs(i.path), abs(i.companions.interface.path)])], options: config.options });
  const checker = program.getTypeChecker();

  const decorators = (n) => (ts.canHaveDecorators(n) ? ts.getDecorators(n) ?? [] : []).map((d) => {
    const e = ts.isCallExpression(d.expression) ? d.expression.expression : d.expression;
    return ts.isIdentifier(e) ? e.text : null;
  });
  const signalKind = (init) => {
    if (!init || !ts.isCallExpression(init)) return null;
    const fn = init.expression;
    const base = ts.isPropertyAccessExpression(fn) ? fn.expression : fn;
    if (!ts.isIdentifier(base)) return null;
    return base.text === 'input' ? 'input' : base.text === 'output' && ts.isIdentifier(fn) ? 'output' : null;
  };
  const baseClass = (decl) => {
    for (const t of checker.getBaseTypes(checker.getTypeAtLocation(decl)) ?? []) {
      const d = t.symbol?.declarations?.find(ts.isClassDeclaration);
      if (d) return d;
    }
    return null;
  };
  const apiOf = (path) => {
    const file = program.getSourceFile(abs(path));
    const cls = file?.statements.filter(ts.isClassDeclaration).find((c) => decorators(c).includes('Component'));
    const names = new Set();
    for (let c = cls, seen = new Set(); c && !seen.has(c); c = baseClass(c)) {
      seen.add(c);
      for (const m of c.members) {
        if (!ts.isPropertyDeclaration(m) || !m.initializer || ts.isPrivateIdentifier(m.name)) continue;
        if (signalKind(m.initializer) || decorators(m).some((d) => d === 'Input' || d === 'Output')) names.add(m.name.getText());
      }
    }
    return names;
  };

  const violations = [];
  for (const item of items) {
    const iface = item.companions.interface;
    if (!iface.exists) { violations.push({ rule: 'component-has-interface', path: item.path, message: `no interface at ${iface.path}` }); continue; }
    const decls = program.getSourceFile(abs(iface.path)).statements.filter(ts.isInterfaceDeclaration);
    const declared = new Set(decls.flatMap((d) => d.members.map((m) => m.name.getText())));
    for (const name of apiOf(item.path)) {
      if (!declared.has(name)) violations.push({ rule: 'interface-matches-api', path: item.path, message: `${iface.path} lacks "${name}"` });
    }
  }
  return { violations };
}

const reply = (obj) => process.stdout.write(JSON.stringify(obj) + '\n');

for await (const line of createInterface({ input: process.stdin })) {
  const { id, method, params } = JSON.parse(line);
  try {
    if (method === 'handshake') reply({ id, result: { protocol: 1, name: 'component-io' } });
    else if (method === 'check') reply({ id, result: check(params) });
    else reply({ id, error: { code: 'unknown-method', message: method } });
  } catch (e) {
    reply({ id, error: { code: e.code ?? 'plugin-bug', message: e.message } });
  }
}
