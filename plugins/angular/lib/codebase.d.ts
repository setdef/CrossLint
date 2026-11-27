// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/codebase.d.ts; a codebase is one tsconfig's TypeScript, and gives a source file by its path.
import { SourceFile } from 'ts-morph';

export declare class Codebase {
  constructor(tsconfig: string);

  sourceFile(path: string): SourceFile;
}
