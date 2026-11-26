import { Component, Input } from '@angular/core';
import { BaseA as Foo } from '../bases/base-a';

@Component({ selector: 'app-c07-local-import-rename', template: '' })
export class LocalImportRenameComponent extends Foo {
  @Input() own = 1;
}
