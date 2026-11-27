// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Node } from 'ts-morph';
import { MissingMember } from './missing-member.js';

// Ported from ng-nudge's lib/artifact/api.js; it keeps public names rather than types, which ng-nudge collected and never compared; reads decorated properties with no initializer, accessors, model(), outputFromObservable(), and aliases; finds a base class through its type, so through mixins; skips static and private members; and takes a source file rather than a path and a project.
export class ComponentApi {
  inputs;
  outputs;

  constructor(inputs, outputs) {
    this.inputs = inputs;
    this.outputs = outputs;
  }

  hasInput(name) {
    return this.inputs.has(name);
  }

  hasOutput(name) {
    return this.outputs.has(name);
  }

  membersMissingFrom(other) {
    const missingInputs = [...this.inputs]
      .filter((name) => !other.hasInput(name))
      .map((name) => new MissingMember('input', name));
    const missingOutputs = [...this.outputs]
      .filter((name) => !other.hasOutput(name))
      .map((name) => new MissingMember('output', name));
    return missingInputs.concat(missingOutputs);
  }

  static from(sourceFile) {
    const componentClass = sourceFile.getClasses().find((c) => c.getDecorator('Component') !== undefined);
    if (!componentClass) return null;

    const inputs = new Set();
    const outputs = new Set();
    const taken = new Set();

    const seen = new Set();
    let current = componentClass;
    while (current && !seen.has(current)) {
      seen.add(current);
      ComponentApi.#collectProperties(current, inputs, outputs, taken);
      current = ComponentApi.#baseClass(current);
    }

    return new ComponentApi(inputs, outputs);
  }

  // A subclass's input or output hides a base class's of the same
  // property name.
  static #collectProperties(cls, inputs, outputs, taken) {
    for (const member of [...cls.getProperties(), ...cls.getGetAccessors(), ...cls.getSetAccessors()]) {
      const name = member.getName();
      if (Node.isPrivateIdentifier(member.getNameNode()) || member.isStatic() || taken.has(name)) continue;

      const signal = Node.isPropertyDeclaration(member) ? ComponentApi.#signal(member.getInitializer()) : null;
      const input = member.getDecorator('Input');
      const output = member.getDecorator('Output');
      const add = (set, publicName) => {
        set.add(publicName);
        taken.add(name);
      };

      if (signal?.kind === 'input') {
        add(inputs, signal.alias ?? name);
      } else if (signal?.kind === 'model') {
        add(inputs, signal.alias ?? name);
        add(outputs, `${signal.alias ?? name}Change`);
      } else if (signal?.kind === 'output') {
        add(outputs, signal.alias ?? name);
      } else if (input) {
        add(inputs, ComponentApi.#decoratorAlias(input) ?? name);
      } else if (output) {
        add(outputs, ComponentApi.#decoratorAlias(output) ?? name);
      }
    }
  }

  // What a property's initializer makes it, and the alias it gives:
  // input(), input.required(), model(), model.required(), output(), or
  // outputFromObservable(), each by the name Angular exports it under.
  static #signal(initializer) {
    if (!initializer || !Node.isCallExpression(initializer)) return null;
    const callee = initializer.getExpression();
    const root = Node.isPropertyAccessExpression(callee) ? callee.getExpression() : callee;
    if (!Node.isIdentifier(root)) return null;

    const required = callee !== root;
    const [first, second] = initializer.getArguments();
    const kind = root.getText();
    if (kind === 'input' || kind === 'model') return { kind, alias: ComponentApi.#alias(required ? first : second) };
    if (required) return null;
    if (kind === 'output') return { kind, alias: ComponentApi.#alias(first) };
    if (kind === 'outputFromObservable') return { kind: 'output', alias: ComponentApi.#alias(second) };
    return null;
  }

  // The alias an options object gives, as in input(0, { alias: 'x' }).
  static #alias(options) {
    if (!options || !Node.isObjectLiteralExpression(options)) return null;
    const property = options.getProperty('alias');
    const value = property && Node.isPropertyAssignment(property) ? property.getInitializer() : null;
    return value && Node.isStringLiteral(value) ? value.getLiteralValue() : null;
  }

  // The alias @Input or @Output gives, as a string or in its options.
  static #decoratorAlias(decorator) {
    const [first] = decorator.getArguments();
    if (first && Node.isStringLiteral(first)) return first.getLiteralValue();
    return ComponentApi.#alias(first);
  }

  // The class a class extends, found through its type, so through
  // imports, path aliases, re-exports, packages, and mixins.
  static #baseClass(cls) {
    const types = cls.getType().getBaseTypes().flatMap((each) => (each.isIntersection() ? each.getIntersectionTypes() : [each]));
    for (const type of types) {
      const declaration = type.getSymbol()?.getDeclarations().find(Node.isClassDeclaration);
      if (declaration) return declaration;
    }
    return null;
  }
}
