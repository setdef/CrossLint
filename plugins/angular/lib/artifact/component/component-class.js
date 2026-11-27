// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { ArtifactFile } from '../artifact-file.js';
import { ComponentApi } from '../api.js';

// Ported from ng-nudge's lib/artifact/component/component-class.js; its path is the one CrossLint gives.
export class ComponentClass extends ArtifactFile {
  get api() {
    return ComponentApi.from(this.sourceFile);
  }
}
