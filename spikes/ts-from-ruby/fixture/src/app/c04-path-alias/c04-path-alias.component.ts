import { Component, input } from '@angular/core';
import { BaseB } from '@app/bases/base-b';

@Component({ selector: 'app-c04-path-alias', template: '' })
export class PathAliasComponent extends BaseB {
  x = input<number>();
}
