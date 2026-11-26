// The Angular plugin's helper: it reads a TypeScript file's component
// class and interfaces with the project's own typescript package, as the
// project's compiler reads them.
//
// Each request is a line of JSON, {"tsconfig": PATH, "path": PATH}, with
// paths relative to the project's root, where CrossLint starts the helper.
// Each answer is a line of JSON: {"component": {"inputs": [NAME],
// "outputs": [NAME]} or null, "interfaces": [[NAME], ...]}, where
// component is the first top-level class with @Component and its base
// classes, and interfaces has the property names of each top-level
// interface, inherited ones included; or {"error": MESSAGE}.
import { createInterface } from 'node:readline';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';

// One program for each tsconfig, which grows by each file asked for that
// the tsconfig leaves out, such as a stub, reusing what it has parsed.
const projects = new Map();

function project(tsconfig) {
  const path = resolve(tsconfig);
  if (projects.has(path)) return projects.get(path);
  let ts;
  try {
    ts = createRequire(resolve(dirname(path), 'package.json'))('typescript');
  } catch {
    throw new Error(`found no typescript package for ${tsconfig}; install the project's packages, as with npm ci`);
  }
  const host = { ...ts.sys, onUnRecoverableConfigFileDiagnostic: (diagnostic) => { throw new Error(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n')); } };
  const parsed = ts.getParsedCommandLineOfConfigFile(path, {}, host);
  const found = { ts, options: parsed.options, roots: new Set(parsed.fileNames), program: undefined };
  projects.set(path, found);
  return found;
}

function sourceFile(found, path) {
  const file = resolve(path);
  const known = found.program?.getSourceFile(file);
  if (known) return known;
  found.roots.add(file);
  found.program = found.ts.createProgram({ rootNames: [...found.roots], options: found.options, oldProgram: found.program });
  return found.program.getSourceFile(file);
}

function read({ tsconfig, path }) {
  const found = project(tsconfig);
  const { ts } = found;
  const file = sourceFile(found, path);
  if (!file) throw new Error(`TypeScript can't read ${path}`);
  const checker = found.program.getTypeChecker();

  const decorators = (node) => (ts.canHaveDecorators(node) ? ts.getDecorators(node) ?? [] : []).map((decorator) => {
    const call = ts.isCallExpression(decorator.expression) ? decorator.expression : null;
    const callee = call ? call.expression : decorator.expression;
    return { name: ts.isIdentifier(callee) ? callee.text : null, arguments: call ? call.arguments : [] };
  });
  const decorated = (node, name) => decorators(node).find((decorator) => decorator.name === name);
  const nameOf = (node) => (ts.isIdentifier(node) || ts.isStringLiteral(node) || ts.isNumericLiteral(node) || ts.isPrivateIdentifier(node) ? node.text : null);
  const isStatic = (member) => (ts.getCombinedModifierFlags(member) & ts.ModifierFlags.Static) !== 0;

  // The alias an options object gives, as in input(0, { alias: 'x' }).
  const alias = (options) => {
    if (!options || !ts.isObjectLiteralExpression(options)) return null;
    const property = options.properties.find((each) => ts.isPropertyAssignment(each) && nameOf(each.name) === 'alias');
    return property && ts.isStringLiteralLike(property.initializer) ? property.initializer.text : null;
  };
  // An alias that @Input or @Output gives as a string or in its options.
  const decoratorAlias = (decorator) => {
    const [first] = decorator.arguments;
    if (first && ts.isStringLiteralLike(first)) return first.text;
    return alias(first);
  };

  // What a property's initializer makes it, and the alias it gives:
  // input(), input.required(), model(), model.required(), output(), and
  // outputFromObservable(), each by the name Angular exports it under.
  const signal = (initializer) => {
    if (!initializer || !ts.isCallExpression(initializer)) return null;
    const callee = initializer.expression;
    const root = ts.isPropertyAccessExpression(callee) ? callee.expression : callee;
    if (!ts.isIdentifier(root)) return null;
    const required = callee !== root;
    const [first, second] = initializer.arguments;
    const options = required ? first : second;
    if (root.text === 'input') return { kind: 'input', alias: alias(options) };
    if (root.text === 'model') return { kind: 'model', alias: alias(options) };
    if (required) return null;
    if (root.text === 'output') return { kind: 'output', alias: alias(first) };
    if (root.text === 'outputFromObservable') return { kind: 'output', alias: alias(second) };
    return null;
  };

  // A subclass's input or output hides a base class's of the same
  // property name, as in ng-nudge.
  const collect = (cls, inputs, outputs, taken) => {
    for (const member of cls.members) {
      const property = ts.isPropertyDeclaration(member);
      if (!property && !ts.isGetAccessor(member) && !ts.isSetAccessor(member)) continue;
      const name = nameOf(member.name);
      if (name === null || ts.isPrivateIdentifier(member.name) || isStatic(member) || taken.has(name)) continue;
      const made = property ? signal(member.initializer) : null;
      const input = decorated(member, 'Input');
      const output = decorated(member, 'Output');
      const add = (list, publicName) => { if (!list.includes(publicName)) list.push(publicName); taken.add(name); };
      if (made?.kind === 'input') add(inputs, made.alias ?? name);
      else if (made?.kind === 'model') { add(inputs, made.alias ?? name); add(outputs, `${made.alias ?? name}Change`); }
      else if (made?.kind === 'output') add(outputs, made.alias ?? name);
      else if (input) add(inputs, decoratorAlias(input) ?? name);
      else if (output) add(outputs, decoratorAlias(output) ?? name);
    }
  };

  // The class a class extends, found through its type, so through
  // imports, path aliases, re-exports, packages, and mixins.
  const base = (cls) => {
    const types = checker.getBaseTypes(checker.getTypeAtLocation(cls)) ?? [];
    for (const type of types.flatMap((each) => (each.isIntersection() ? each.types : [each]))) {
      const declaration = type.symbol?.declarations?.find(ts.isClassDeclaration);
      if (declaration) return declaration;
    }
    return null;
  };

  const component = () => {
    const cls = file.statements.filter(ts.isClassDeclaration).find((each) => decorated(each, 'Component'));
    if (!cls) return null;
    const inputs = [];
    const outputs = [];
    const taken = new Set();
    for (let each = cls, seen = new Set(); each && !seen.has(each); each = base(each)) {
      seen.add(each);
      collect(each, inputs, outputs, taken);
    }
    return { inputs, outputs };
  };

  const interfaces = () => file.statements.filter(ts.isInterfaceDeclaration).map((declaration) => {
    const type = checker.getDeclaredTypeOfSymbol(checker.getSymbolAtLocation(declaration.name));
    return checker.getPropertiesOfType(type).filter((symbol) => symbol.declarations?.some(ts.isPropertySignature)).map((symbol) => symbol.name);
  });

  return { component: component(), interfaces: interfaces() };
}

for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  let answer;
  try {
    answer = read(JSON.parse(line));
  } catch (error) {
    answer = { error: error.message };
  }
  process.stdout.write(`${JSON.stringify(answer)}\n`);
}
