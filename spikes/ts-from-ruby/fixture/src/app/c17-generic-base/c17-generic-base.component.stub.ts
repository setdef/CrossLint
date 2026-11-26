import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c17-generic-base-stub', template: '' })
export class GenericBaseComponentStub {
  own = input<unknown>();
  genOut = output<unknown>();
}
