// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/codebase.d.ts and lib/verification-task.d.ts; the helper answers CrossLint's requests, one per line of JSON.
import { Artifact, Setting } from './artifacts';
import { Violation } from './violation';

export interface Piece {
  path: string;
  exists: boolean;
}

export interface CheckedArtifact {
  path: string;
  role: string;
  match: Record<string, string>;
  key: string | null;
  companions: Record<string, Piece>;
}

export declare function answer(
  request: { settings: Setting[] } | { rule: string; artifact: CheckedArtifact }
): Promise<{ artifacts: Artifact[] } | { mistake: { message: string; line: number } } | { violations: Violation[] }>;
