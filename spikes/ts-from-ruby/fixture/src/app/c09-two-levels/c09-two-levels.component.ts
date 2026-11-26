import { Component, input } from '@angular/core';
import { Mid } from '../bases/mid';

@Component({ selector: 'app-c09-two-levels', template: '' })
export class TwoLevelsComponent extends Mid {
  top = input<string>();
}
