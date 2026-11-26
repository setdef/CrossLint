// Builds a Violation the way the ng-nudge README's "Adding custom rules"
// example does: a violation with a subject and a message, and no rule.
import { Violation } from '../../../node_modules/@overthetopmarketing/ng-nudge/lib/violation.js';

export class NeedsNote {
  applies(artifact) {
    return artifact.role === 'service';
  }

  rules(_artifact) {
    return [];
  }

  violations(artifact) {
    if (!this.applies(artifact)) return [];
    return [new Violation(artifact, 'note missing')];
  }
}
