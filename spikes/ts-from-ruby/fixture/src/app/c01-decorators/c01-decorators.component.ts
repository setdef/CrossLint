import { Component, EventEmitter, HostBinding, Input, Output, input } from '@angular/core';

@Component({ selector: 'app-c01-decorators', template: '' })
export class DecoratorsComponent {
  @Input() withInit = 'a';
  @Input() noInit!: string;
  @Input({ required: true }) req!: number;
  @Input('aliasName') aliased = 1;
  @Input() set viaSetter(v: string) {}
  @Output() changed = new EventEmitter<string>();
  @Output() noInitOut!: EventEmitter<void>;
  #secret = input<string>();
  notAnInput = 5;
  @HostBinding('class') cls = 'x';
}
