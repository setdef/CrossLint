// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/codebase.js; a codebase is the TypeScript one tsconfig describes, read with ts-morph, and its artifacts and policies are CrossLint's.
import { resolve } from 'node:path';
import { Project } from 'ts-morph';

// The TypeScript a tsconfig describes, read with ts-morph. It grows by
// each file asked for that the tsconfig leaves out, such as a stub, and
// reuses what it has parsed.
export class Codebase {
  #project;

  constructor(tsconfig) {
    this.#project = new Project({ tsConfigFilePath: resolve(tsconfig) });
  }

  sourceFile(path) {
    const full = resolve(path);
    const found = this.#project.getSourceFile(full) ?? this.#project.addSourceFileAtPathIfExists(full);
    if (!found) throw new Error(`TypeScript can't read ${path}`);
    return found;
  }
}
