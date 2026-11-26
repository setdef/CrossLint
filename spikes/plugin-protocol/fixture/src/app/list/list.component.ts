import { Component, Input } from '@angular/core';
import { Base } from '../base/base';

@Component({ selector: 'app-list', templateUrl: './list.component.html' })
export class ListComponent extends Base {
  @Input() items: string[] = [];
}
