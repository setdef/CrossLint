import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c03-relative-stub', template: '' })
export class RelativeComponentStub {
  own = input<unknown>();
  baseAInit = input<unknown>();
  baseASig = input<unknown>();
  shared = input<unknown>();
  baseAOut = output<unknown>();
  baseAEvt = output<unknown>();
}
