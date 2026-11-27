// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/artifact/missing-member.d.ts; unchanged.
export declare class MissingMember {
    kind: 'input' | 'output';
    name: string;
    constructor(kind: 'input' | 'output', name: string);
    toString(): string;
}
