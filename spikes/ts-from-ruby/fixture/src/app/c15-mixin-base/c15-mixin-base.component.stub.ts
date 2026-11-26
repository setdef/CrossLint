import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c15-mixin-base-stub', template: '' })
export class MixinBaseComponentStub {
  own = input<unknown>();
  mixIn = input<unknown>();
  baseAInit = input<unknown>();
  baseASig = input<unknown>();
  shared = input<unknown>();
  baseAOut = output<unknown>();
  baseAEvt = output<unknown>();
}
