// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { Codebase } from '../codebase';
import { ComponentClass } from './component/component-class';
import { Stub } from './component/stub';
import { Interface } from './component/interface';

// Ported from ng-nudge's lib/artifact/component.artifact.d.ts; only the pieces the helper reads.
export declare class Component {
  constructor(project: Codebase, paths: { path: string; stub?: string; interface?: string });

  get project(): Codebase;
  get class(): ComponentClass;
  get stub(): Stub | undefined;
  get interface(): Interface | undefined;
}
