// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

import { ArtifactFile } from '../artifact-file';
import { InterfaceApi } from '../interface-api';

// Ported from ng-nudge's lib/artifact/component/interface.d.ts; apis replaces api.
export declare class Interface extends ArtifactFile {
  get apis(): InterfaceApi[];
}
