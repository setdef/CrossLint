import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c01-decorators-stub', template: '' })
export class DecoratorsComponentStub {
  withInit = input<unknown>();
  aliased = input<unknown>();
  changed = output<unknown>();
}
