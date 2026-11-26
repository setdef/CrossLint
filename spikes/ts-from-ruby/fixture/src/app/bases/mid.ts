import { input } from '@angular/core';
import { BaseA } from '@app/bases/base-a';

export class Mid extends BaseA {
  midIn = input<string>();
  override shared = input<string>('from mid');
}
