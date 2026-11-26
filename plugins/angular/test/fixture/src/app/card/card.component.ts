import { Component, EventEmitter, Input, Output, input, model, output } from '@angular/core';
import { outputFromObservable } from '@angular/core/rxjs-interop';
import { Subject } from 'rxjs';
import { Titled } from '@shared/titled';

// Every form of input and output the helper reads, and a base class
// through a path alias.
@Component({ selector: 'app-card', template: '' })
export class CardComponent extends Titled {
  @Input() withInit = 'a';
  @Input() noInit!: string;
  @Input('caption') label = '';
  @Input() set size(value: number) {}
  @Output() closed = new EventEmitter<void>();
  count = input(0);
  total = input.required<number>();
  hint = input('', { alias: 'tip' });
  open = model(false);
  picked = output<string>();
  changes = outputFromObservable(new Subject<string>());
  #secret = input('x');
  notAnInput = 5;
}
