// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/violation.d.ts; a message and a detail, and no subject, severity, or rule.
export declare class Violation {
  message: string;
  detail: string | null;

  constructor(message: string, detail?: string | null);
}
