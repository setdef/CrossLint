import { Component, input, output } from '@angular/core';

// The members ng-nudge reads of the component, and none it skips.
@Component({ selector: 'app-card', template: '' })
export class CardComponentStub {
  title = input('');
  withInit = input('a');
  label = input('');
  closed = output<void>();
  count = input(0);
  total = input(0);
  hint = input('');
  picked = output<string>();
}
