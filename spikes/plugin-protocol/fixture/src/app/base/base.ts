import { Input, input } from '@angular/core';

export class Base {
  @Input() inheritedDecorated = '';
  inheritedSignal = input<string>();
}
