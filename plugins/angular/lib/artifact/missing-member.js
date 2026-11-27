// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/artifact/missing-member.js; unchanged.
export class MissingMember {
  kind;
  name;

  constructor(kind, name) {
    this.kind = kind;
    this.name = name;
  }

  toString() {
    return `${this.kind}: ${this.name}`;
  }
}
