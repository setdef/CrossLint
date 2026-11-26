import { EventEmitter, Input, Output, input, output } from '@angular/core';

export class BaseA {
  @Input() baseAInit = '';
  @Input() baseANoInit!: string;
  baseASig = input<string>();
  baseAOut = output<void>();
  @Output() baseAEvt = new EventEmitter<number>();
  shared = input<string>('from base a');
}
