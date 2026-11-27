// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/violation.js; a violation keeps its message and a detail, and its subject, severity, and rule are CrossLint's.
// What a rule reports, as the helper answers it to CrossLint: a
// message, and the detail that tells apart one artifact's violations of
// one rule.
export class Violation {
  message;
  detail;

  constructor(message, detail = null) {
    this.message = message;
    this.detail = detail;
  }
}
