import { Component, Input, output } from '@angular/core';

@Component({ selector: 'app-multi', templateUrl: './multi.component.html' })
export class MultiComponent {
  @Input() alpha = '';
  @Input() beta = '';
  gamma = output<boolean>();
}
