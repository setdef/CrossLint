// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Component } from '../artifact/component.artifact';
import { Violation } from '../violation';

// Ported from ng-nudge's lib/rule/types.d.ts; a rule's subject is a component.
export interface Rule {
  readonly violations: Violation[];
}

export interface RuleConstructor {
  name: string;
  new (artifact: Component): Rule;
}
