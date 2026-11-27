// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { SourceFile } from 'ts-morph';
import { MissingMember } from './missing-member';

// Ported from ng-nudge's lib/artifact/api.d.ts; inputs and outputs are sets of public names, and from takes a source file.
export declare class ComponentApi {
  inputs: Set<string>;
  outputs: Set<string>;

  constructor(inputs: Set<string>, outputs: Set<string>);

  hasInput(name: string): boolean;
  hasOutput(name: string): boolean;
  membersMissingFrom(other: { hasInput(name: string): boolean; hasOutput(name: string): boolean }): MissingMember[];

  static from(sourceFile: SourceFile): ComponentApi | null;
}
