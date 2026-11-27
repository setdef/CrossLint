// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Rule } from './rule.js';

// Ported from ng-nudge's lib/rule/stub-matches-component.rule.js; a stub with no @Component class is a violation, where ng-nudge passed it, and each violation's detail names its member.
export class StubMatchesComponent extends Rule {
  static name = 'stub-matches-component';

  check() {
    const componentApi = this.artifact.class.api;
    const stubApi = this.artifact.stub.api;

    if (!componentApi) return [];
    if (!stubApi) return [this.violation(`stub file at ${this.artifact.stub.path} has no @Component class`)];

    return componentApi.membersMissingFrom(stubApi)
      .map((member) => this.violation(`stub missing ${member}`, `${member.kind} ${member.name}`));
  }
}
