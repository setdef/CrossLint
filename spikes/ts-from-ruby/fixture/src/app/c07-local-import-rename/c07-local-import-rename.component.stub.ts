import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c07-local-import-rename-stub', template: '' })
export class LocalImportRenameComponentStub {
  own = input<unknown>();
  baseAInit = input<unknown>();
  baseASig = input<unknown>();
  shared = input<unknown>();
  baseAOut = output<unknown>();
  baseAEvt = output<unknown>();
}
