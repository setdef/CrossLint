import { Component, computed, input, model, output, outputFromObservable, signal } from '@angular/core';
import { Subject } from 'rxjs';

@Component({ selector: 'app-c02-signals', template: '' })
export class SignalsComponent {
  a = input<string>();
  b = input.required<number>();
  c = input(0, { alias: 'cc' });
  d = output<string>();
  e = model<boolean>(false);
  f = model.required<string>();
  g = computed(() => 1);
  h = signal(0);
  i = input.required<string>({ alias: 'ii' });
  j = outputFromObservable(new Subject<string>());
  k = input<string, number>(0, { transform: (v: number) => String(v) });
}
