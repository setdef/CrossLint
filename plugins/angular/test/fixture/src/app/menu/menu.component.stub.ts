import { Component, input, output } from '@angular/core';

// A stub with every member, and one the component lacks.
@Component({ selector: 'app-menu', template: '' })
export class MenuComponentStub {
  items = input<string[]>([]);
  selected = output<string>();
  extra = input('');
}
