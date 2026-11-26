import { Component, Input, input, model } from '@angular/core';
import { outputFromObservable } from '@angular/core/rxjs-interop';
import { Subject } from 'rxjs';
import { Labelled } from './labelled';

@Component({ selector: 'app-field', template: '' })
export class FieldComponent extends Labelled {
  label = input('', { alias: 'caption' });
  @Input() hint: string;
  value = model<string>();
  @Input() set size(size: number) {}
  changed = outputFromObservable(new Subject<string>());
}
