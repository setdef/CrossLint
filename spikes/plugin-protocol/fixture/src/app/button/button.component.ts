import { Component, EventEmitter, Input, Output } from '@angular/core';

@Component({ selector: 'app-button', templateUrl: './button.component.html' })
export class ButtonComponent {
  @Input() label = '';
  @Output() pressed = new EventEmitter<void>();
}
