import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c14-directory-import-stub', template: '' })
export class DirectoryImportComponentStub {
  own = input<unknown>();
  baseAInit = input<unknown>();
  baseASig = input<unknown>();
  shared = input<unknown>();
  baseAOut = output<unknown>();
  baseAEvt = output<unknown>();
}
