// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { ComponentClass } from './component/component-class.js';
import { Stub } from './component/stub.js';
import { Interface } from './component/interface.js';

// Ported from ng-nudge's lib/artifact/component.artifact.js; a component has the pieces a rule reads, at the paths CrossLint gives, and its project; its spec and stylesheets are CrossLint's to check, from the filesystem.
export class Component {
  #project;
  #class;
  #stub;
  #interface;

  constructor(project, { path, stub, interface: iface }) {
    this.#project = project;
    this.#class = new ComponentClass(this, path);
    this.#stub = stub && new Stub(this, stub);
    this.#interface = iface && new Interface(this, iface);
  }

  get project() {
    return this.#project;
  }

  get class() {
    return this.#class;
  }

  get stub() {
    return this.#stub;
  }

  get interface() {
    return this.#interface;
  }
}
