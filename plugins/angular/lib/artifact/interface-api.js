// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Node } from 'ts-morph';

// Ported from ng-nudge's lib/artifact/interface-api.js; all reads every interface in a file, where from threw for more or fewer than one, and each includes the properties its interface inherits.
export class InterfaceApi {
  properties;

  constructor(properties) {
    this.properties = properties;
  }

  hasInput(name) {
    return this.properties.has(name);
  }

  hasOutput(name) {
    return this.properties.has(name);
  }

  static all(sourceFile) {
    return sourceFile.getInterfaces().map((iface) => {
      const properties = iface.getType().getProperties()
        .filter((symbol) => symbol.getDeclarations().some(Node.isPropertySignature))
        .map((symbol) => symbol.getName());
      return new InterfaceApi(new Set(properties));
    });
  }
}
