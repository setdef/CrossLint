// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { ArtifactFile } from '../artifact-file';
import { ComponentApi } from '../api';

// Ported from ng-nudge's lib/artifact/component/component-class.d.ts; it has no suffix, since its path is given.
export declare class ComponentClass extends ArtifactFile {
  get api(): ComponentApi | null;
}
