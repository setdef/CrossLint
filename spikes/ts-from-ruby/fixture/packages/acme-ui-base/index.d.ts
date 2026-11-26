import type * as i0 from '@angular/core';
import type { EventEmitter, InputSignal, OutputEmitterRef } from '@angular/core';

export declare class UiBase {
  readonly pkgSignalIn: InputSignal<string>;
  readonly pkgOut: OutputEmitterRef<string>;
  pkgDecIn: string;
  pkgEvt: EventEmitter<void>;
  static ɵcmp: i0.ɵɵComponentDeclaration<UiBase, "acme-ui-base", never, { "pkgSignalIn": { "alias": "pkgSignalIn"; "required": true; "isSignal": true; }; "pkgDecIn": { "alias": "pkgDecIn"; "required": false; }; }, { "pkgOut": "pkgOut"; "pkgEvt": "pkgEvt"; }, never, never, true, never>;
}
