// Approach B: a helper that an Angular plugin could carry. It uses the
// TypeScript compiler API, which an Angular project already has installed.
// Reads {"tsconfig": PATH, "strict": BOOL, "components": [PATH], "interfaces": [PATH]}
// on stdin, writes {"components": {PATH: {inputs, outputs} | null}, "interfaces": {PATH: [name] | {error}}}.
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { readFileSync } from 'node:fs';

const request = JSON.parse(readFileSync(0, 'utf8'));
// Load the TypeScript the project itself uses, not one bundled with the helper.
const ts = createRequire(resolve(dirname(request.tsconfig), 'noop.js'))('typescript');
const { strict } = request;

const config = ts.getParsedCommandLineOfConfigFile(request.tsconfig, {}, {
  ...ts.sys, onUnRecoverableConfigFileDiagnostic: (d) => { throw new Error(ts.flattenDiagnosticMessageText(d.messageText, '\n')); },
});
const files = [...config.fileNames, ...request.components, ...request.interfaces];
const program = ts.createProgram({ rootNames: files, options: config.options });
const checker = program.getTypeChecker();

const decoratorNames = (node) => (ts.canHaveDecorators(node) ? ts.getDecorators(node) ?? [] : []).map((d) => {
  const e = ts.isCallExpression(d.expression) ? d.expression.expression : d.expression;
  return ts.isIdentifier(e) ? e.text : null;
});

const isStatic = (m) => m.modifiers?.some((x) => x.kind === ts.SyntaxKind.StaticKeyword);
const nameOf = (m) => (ts.isPrivateIdentifier(m.name) ? m.name.text : ts.isStringLiteral(m.name) ? m.name.text : m.name.getText());

// ng-nudge's test for `input(...)`, `input.required(...)`, `output(...)`.
function callKind(init) {
  if (!ts.isCallExpression(init)) return null;
  const fn = init.expression;
  const root = ts.isPropertyAccessExpression(fn) ? fn.expression : fn;
  if (!ts.isIdentifier(root)) return null;
  if (root.text === 'input') return 'input';
  if (root.text === 'output' && ts.isIdentifier(fn)) return 'output';
  if (strict && root.text === 'outputFromObservable' && ts.isIdentifier(fn)) return 'output';
  if (strict && root.text === 'model') return 'model';
  return null;
}

// The class this one extends, found by the type checker: it follows imports,
// path aliases, re-exports and packages, and sees through `mixin(Base)`.
function baseClass(decl) {
  const type = checker.getTypeAtLocation(decl);
  const bases = (checker.getBaseTypes(type) ?? []).flatMap((t) => (t.isIntersection() ? t.types : [t]));
  for (const t of bases) {
    const d = t.symbol?.declarations?.find(ts.isClassDeclaration);
    if (d) return d;
  }
  return null;
}

function collect(cls, inputs, outputs) {
  const add = (list, n) => { if (!list.includes(n)) list.push(n); };
  for (const m of cls.members) {
    if (ts.isPropertyDeclaration(m) && (!isStatic(m) || strict)) {
      const name = nameOf(m);
      if (name.startsWith('#') || inputs.includes(name) || outputs.includes(name)) continue;
      if (strict && isStatic(m) && (name === 'ɵcmp' || name === 'ɵdir')) { declarationMetadata(m, inputs, outputs); continue; }
      if (isStatic(m)) continue;
      if (!m.initializer && !strict) continue;
      const kind = m.initializer && callKind(m.initializer);
      const decos = decoratorNames(m);
      if (kind === 'input') add(inputs, name);
      else if (kind === 'output') add(outputs, name);
      else if (kind === 'model') { add(inputs, name); add(outputs, `${name}Change`); }
      else if (decos.includes('Input')) add(inputs, name);
      else if (decos.includes('Output')) add(outputs, name);
    } else if (strict && (ts.isGetAccessor(m) || ts.isSetAccessor(m))) {
      const name = nameOf(m);
      const decos = decoratorNames(m);
      if (decos.includes('Input')) add(inputs, name);
      if (decos.includes('Output')) add(outputs, name);
    }
  }
}

// Angular records a library class's inputs and outputs in the type arguments of `static ɵcmp`.
function declarationMetadata(prop, inputs, outputs) {
  const args = prop.type?.typeArguments ?? [];
  const keys = (t) => (t && ts.isTypeLiteralNode(t) ? t.members.map((p) => nameOf(p)) : []);
  for (const n of keys(args[3])) if (!inputs.includes(n)) inputs.push(n);
  for (const n of keys(args[4])) if (!outputs.includes(n)) outputs.push(n);
}

function componentApi(path) {
  const file = program.getSourceFile(path);
  if (!file) return null;
  const classes = file.statements.filter(ts.isClassDeclaration);
  const cls = classes.find((c) => decoratorNames(c).includes('Component'));
  if (!cls) return null;
  const inputs = [], outputs = [], seen = new Set();
  for (let c = cls; c && !seen.has(c); c = baseClass(c)) { seen.add(c); collect(c, inputs, outputs); }
  return { inputs, outputs };
}

function interfaceNames(path) {
  const file = program.getSourceFile(path);
  if (!file) return null;
  const ifaces = file.statements.filter(ts.isInterfaceDeclaration);
  if (ifaces.length !== 1) return { error: `Expected exactly 1 interface in ${path}, found ${ifaces.length}` };
  return ifaces[0].members.filter(ts.isPropertySignature).map(nameOf);
}

const out = { components: {}, interfaces: {} };
for (const p of request.components) out.components[p] = componentApi(p);
for (const p of request.interfaces) out.interfaces[p] = interfaceNames(p);
process.stdout.write(JSON.stringify(out));
