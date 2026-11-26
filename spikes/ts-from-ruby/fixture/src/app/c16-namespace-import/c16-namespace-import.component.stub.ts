import { Component, input, output } from '@angular/core';

@Component({ selector: 'app-c16-namespace-import-stub', template: '' })
export class NamespaceImportComponentStub {
  own = input<unknown>();
  nsIn = input<unknown>();
}
