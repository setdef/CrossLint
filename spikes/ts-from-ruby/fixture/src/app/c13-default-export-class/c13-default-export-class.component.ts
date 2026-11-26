import { Component, input } from '@angular/core';

class Helper {
  helperIn = input<string>();
}

@Component({ selector: 'app-c13-default-export-class', template: '' })
export default class DefaultExportClassComponent {
  own = input<string>();
}
