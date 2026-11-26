import { Component, input } from '@angular/core';
import * as bases from '../bases/ns';

@Component({ selector: 'app-c16-namespace-import', template: '' })
export class NamespaceImportComponent extends bases.NsBase {
  own = input<string>();
}
