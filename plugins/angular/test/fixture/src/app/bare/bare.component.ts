import { Component, input } from '@angular/core';

@Component({ selector: 'app-bare', template: '' })
export class BareComponent {
  value = input(0);
}
