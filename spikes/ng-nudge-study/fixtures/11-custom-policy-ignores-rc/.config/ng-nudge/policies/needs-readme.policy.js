import { Rule } from '@overthetopmarketing/ng-nudge/rules';

class ReadmeExists extends Rule {
  static name = 'readme-exists';

  check() {
    return [this.violation('readme missing')];
  }
}

export class NeedsReadme {
  #config;

  constructor(config) {
    this.#config = config;
  }

  applies(artifact) {
    return artifact.role === 'service';
  }

  rules(artifact) {
    return [new ReadmeExists(artifact, this.#config)];
  }

  violations(artifact) {
    if (!this.applies(artifact)) return [];
    return this.rules(artifact).flatMap((rule) => rule.violations);
  }
}
