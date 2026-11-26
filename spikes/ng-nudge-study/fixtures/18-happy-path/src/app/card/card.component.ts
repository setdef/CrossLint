import { Component, input } from '@angular/core';

@Component({ selector: 'app-card', template: '' })
export class CardComponent {
  title = input<string>();
}
