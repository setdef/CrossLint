import { Input, input } from '@angular/core';

export class BaseC {
  @Input() cDec = 'c';
  cSig = input<number>();
}
