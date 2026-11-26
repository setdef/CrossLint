import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c02-signals-stub', template: '' })
export class SignalsComponentStub {
  a = input<unknown>();
  b = input<unknown>();
  c = input<unknown>();
  d = output<unknown>();
}
