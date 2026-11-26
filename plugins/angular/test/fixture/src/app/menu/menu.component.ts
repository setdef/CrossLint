import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-menu', template: '' })
export class MenuComponent {
  items = input<string[]>([]);
  selected = output<string>();
}
