// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/config/artifact-definition.d.ts and lib/config/registry/artifact.registry.d.ts; roles come from CrossLint's settings.
export interface Setting {
  name: string;
  arguments: unknown[];
  properties: Record<string, unknown>;
  children: Setting[];
  line: number;
}

export interface Artifact {
  name: string;
  files: string;
  companions: Record<string, string>;
  key: string;
  optional: boolean;
  dotfiles: boolean;
}

export declare const ROLES: string[];

export declare class Mistake extends Error {
  line: number;
  constructor(message: string, setting: Setting);
}

export declare function declare(settings: Setting[]): Artifact[];
