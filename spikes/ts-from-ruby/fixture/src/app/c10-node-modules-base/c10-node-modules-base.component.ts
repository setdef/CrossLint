import { Component, input } from '@angular/core';
import { UiBase } from '@acme/ui-base';

@Component({ selector: 'app-c10-node-modules-base', template: '' })
export class NodeModulesBaseComponent extends UiBase {
  ownP = input<string>();
}
