import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c12-same-file-base-stub', template: '' })
export class SameFileBaseComponentStub {
  own = input<unknown>();
  localIn = input<unknown>();
}
