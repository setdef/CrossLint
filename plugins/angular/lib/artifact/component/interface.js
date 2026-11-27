// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { ArtifactFile } from '../artifact-file.js';
import { InterfaceApi } from '../interface-api.js';

// Ported from ng-nudge's lib/artifact/component/interface.js; its path is the one CrossLint gives, and it has an API for each interface in the file.
export class Interface extends ArtifactFile {
  get apis() {
    return InterfaceApi.all(this.sourceFile);
  }
}
