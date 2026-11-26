import { Input, input } from '@angular/core';

export class Labelled {
  id = input<string>();
  @Input() tone = 'plain';
}
