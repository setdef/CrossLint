// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Rule } from './rule.js';

// Ported from ng-nudge's lib/rule/interface-matches-component.rule.js; an interface file without exactly one interface is a violation, where ng-nudge threw and stopped every check, and each violation's detail names its member.
export class InterfaceMatchesComponent extends Rule {
  static name = 'interface-matches-component';

  check() {
    const componentApi = this.artifact.class.api;
    const interfaceApis = this.artifact.interface.apis;

    if (!componentApi) return [];
    if (interfaceApis.length !== 1) {
      const count = interfaceApis.length === 0 ? 'no interface' : `${interfaceApis.length} interfaces`;
      return [this.violation(`interface file at ${this.artifact.interface.path} has ${count}, where it should have one`)];
    }

    return componentApi.membersMissingFrom(interfaceApis[0])
      .map((member) => this.violation(`interface missing ${member}`, `${member.kind} ${member.name}`));
  }
}
