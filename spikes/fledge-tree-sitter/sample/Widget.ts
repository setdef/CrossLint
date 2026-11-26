import { Component, Input, Output, EventEmitter } from "@angular/core";

@Component({ selector: "app-widget", templateUrl: "./widget.component.html" })
export class WidgetComponent extends BaseComponent {
  @Input() label = "";
  @Input({ required: true }) id!: string;
  @Output() picked = new EventEmitter<string>();
  plain = 1;

  @HostListener("window:resize")
  onResize() {}
}

export abstract class Base {
  @Input() inherited = 0;
}
