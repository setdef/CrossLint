import { Component, EventEmitter, Input, Output, output } from '@angular/core';

@Component({ selector: 'app-card', templateUrl: './card.component.html' })
export class CardComponent {
  @Input() title = '';
  @Output() closed = new EventEmitter<void>();
  expanded = output<boolean>();
}
