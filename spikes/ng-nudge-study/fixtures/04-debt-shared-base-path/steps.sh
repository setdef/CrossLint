# Record the component's missing spec as debt.
nudge --update-debt
show cat .config/ng-nudge/debt.tsv
# Add a service with the same base name and no spec. Its new violation is
# excused by the component's debt entry, and the run passes.
cat > src/app/foo/foo.service.ts <<'TS'
export class FooService {}
TS
show ls src/app/foo
nudge
