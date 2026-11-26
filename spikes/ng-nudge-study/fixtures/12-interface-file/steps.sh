# CardApi gets title from Titled, which ng-nudge doesn't follow.
show cat src/app/card/card.component.i.d.ts
nudge
# A second interface in the file aborts the whole run: no other artifact
# (other.service.ts lacks a spec) is reported.
cat > src/app/card/card.component.i.d.ts <<'TS'
export interface CardApi {
  title: string;
}

export interface CardEvents {}
TS
nudge
