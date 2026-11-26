import { Component, input } from '@angular/core';
import { GenericBase } from '../bases/generic';

@Component({ selector: 'app-c17-generic-base', template: '' })
export class GenericBaseComponent extends GenericBase<string> {
  own = input<string>();
}
