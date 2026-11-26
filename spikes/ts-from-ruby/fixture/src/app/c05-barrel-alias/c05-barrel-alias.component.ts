import { Component, Input } from '@angular/core';
import { BaseC } from '@shared';

@Component({ selector: 'app-c05-barrel-alias', template: '' })
export class BarrelAliasComponent extends BaseC {
  @Input() cOwn = 1;
}
