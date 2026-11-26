import { input, output } from '@angular/core';

export class GenericBase<T> {
  genIn = input<T>();
  genOut = output<T>();
}
