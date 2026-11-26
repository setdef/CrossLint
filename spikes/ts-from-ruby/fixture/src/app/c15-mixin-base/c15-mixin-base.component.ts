import { Component, input } from '@angular/core';
import { BaseA } from '../bases/base-a';
import { withMixIn } from '../bases/mixin';

@Component({ selector: 'app-c15-mixin-base', template: '' })
export class MixinBaseComponent extends withMixIn(BaseA) {
  own = input<string>();
}
