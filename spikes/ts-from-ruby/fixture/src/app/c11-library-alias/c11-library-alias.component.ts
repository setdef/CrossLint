import { Component, input } from '@angular/core';
import { LibBase } from '@lib/ui';

@Component({ selector: 'app-c11-library-alias', template: '' })
export class LibraryAliasComponent extends LibBase {
  ownL = input<string>();
}
