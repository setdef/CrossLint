import { Rule } from '@overthetopmarketing/ng-nudge/rules';

export class AlwaysFails extends Rule {
  static name = 'always-fails';

  check() {
    return [this.violation('this rule always fails')];
  }
}
