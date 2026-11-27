// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Component } from '../artifact/component.artifact';
import { Violation } from '../violation';

// Ported from ng-nudge's lib/rule/rule.d.ts; no severity or configuration.
export declare class Rule {
  static name: string;

  constructor(artifact: Component);

  get artifact(): Component;

  violation(message: string, detail?: string | null): Violation;
  check(): Violation[];
  get violations(): Violation[];
}
