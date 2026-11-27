// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { SourceFile } from 'ts-morph';
import { Component } from './component.artifact';

// Ported from ng-nudge's lib/artifact/artifact-file.d.ts; a piece has a path given to it and a source file, and no exists.
export declare class ArtifactFile {
  constructor(artifact: Component, path: string);

  get artifact(): Component;
  get path(): string;
  get sourceFile(): SourceFile;
}
