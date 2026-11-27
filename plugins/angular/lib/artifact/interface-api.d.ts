// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { SourceFile } from 'ts-morph';

// Ported from ng-nudge's lib/artifact/interface-api.d.ts; all replaces from.
export declare class InterfaceApi {
    properties: Set<string>;
    constructor(properties: Set<string>);
    hasInput(name: string): boolean;
    hasOutput(name: string): boolean;
    static all(sourceFile: SourceFile): InterfaceApi[];
}
