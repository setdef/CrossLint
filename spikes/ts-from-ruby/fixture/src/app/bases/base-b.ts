import { Directive, Input, input, model } from '@angular/core';

@Directive()
export abstract class BaseB {
  bReq = input.required<string>();
  @Input() bDec = 0;
  bModel = model<number>(0);
}
