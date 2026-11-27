// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Violation } from '../violation.js';

// Ported from ng-nudge's lib/rule/rule.js; a rule's severity and whether it runs are CrossLint's, from the plugin's policies and the project's configuration, so the rule keeps only its artifact; violation takes a detail.
export class Rule {
  static name = 'unnamed';

  #artifact;

  constructor(artifact) {
    this.#artifact = artifact;
  }

  get artifact() {
    return this.#artifact;
  }

  violation(message, detail = null) {
    return new Violation(message, detail);
  }

  get violations() {
    return this.check();
  }

  check() {
    throw new Error('Subclass must implement check()');
  }
}
