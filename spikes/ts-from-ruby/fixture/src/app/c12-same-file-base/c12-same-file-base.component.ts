import { Component, Input } from '@angular/core';

class LocalBase {
  @Input() localIn = 1;
}

@Component({ selector: 'app-c12-same-file-base', template: '' })
export class SameFileBaseComponent extends LocalBase {
  @Input() own = 2;
}
