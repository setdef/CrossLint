import { input } from '@angular/core';

export function withMixIn<T extends new (...args: any[]) => object>(Base: T) {
  return class extends Base {
    mixIn = input<string>();
  };
}
