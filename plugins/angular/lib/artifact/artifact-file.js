// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// Ported from ng-nudge's lib/artifact/artifact-file.js; a piece has the path CrossLint gives it, and its source file from the artifact's project; whether it exists is CrossLint's to say, from the filesystem.
export class ArtifactFile {
  #artifact;
  #path;

  constructor(artifact, path) {
    this.#artifact = artifact;
    this.#path = path;
  }

  get artifact() {
    return this.#artifact;
  }

  get path() {
    return this.#path;
  }

  get sourceFile() {
    return this.#artifact.project.sourceFile(this.#path);
  }
}
