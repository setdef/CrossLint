import { Component, input } from '@angular/core';
import { BaseA } from '../bases';

@Component({ selector: 'app-c14-directory-import', template: '' })
export class DirectoryImportComponent extends BaseA {
  own = input<string>();
}
