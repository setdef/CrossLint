import { Component, Input } from '@angular/core';

@Component({ selector: 'app-footer', template: '<footer></footer>' })
export class FooterComponent {
  @Input() text = '';
}
