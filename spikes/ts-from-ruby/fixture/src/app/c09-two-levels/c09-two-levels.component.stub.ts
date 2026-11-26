import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c09-two-levels-stub', template: '' })
export class TwoLevelsComponentStub {
  top = input<unknown>();
  midIn = input<unknown>();
  shared = input<unknown>();
  baseAInit = input<unknown>();
  baseASig = input<unknown>();
  baseAOut = output<unknown>();
  baseAEvt = output<unknown>();
}
