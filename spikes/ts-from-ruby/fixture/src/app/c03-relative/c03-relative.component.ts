import { Component, Input, input } from '@angular/core';
import { BaseA } from '../bases/base-a';

@Component({ selector: 'app-c03-relative', template: '' })
export class RelativeComponent extends BaseA {
  @Input() own = 1;
  override shared = input<string>('child');
}
