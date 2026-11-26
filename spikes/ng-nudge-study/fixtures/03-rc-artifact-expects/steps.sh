# Control: a "store" artifact with a pattern and no "expects" gets the
# default companion, a spec file, and its missing spec is reported.
show cat .config/ng-nudge/rc.json
nudge
# The schema documents "expects" as a list of strings. Any list makes
# ng-nudge stop checking the artifact: the store is no longer listed at all.
echo '{ "artifacts": { "store": { "pattern": "**/*.store.ts", "expects": ["spec"] } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/rc.json
nudge
# Overriding a built-in artifact's "expects" is ignored: the service is
# still checked for a spec after "expects": [] (its spec is deleted here).
echo '{ "artifacts": { "service": { "expects": [] } } }' > .config/ng-nudge/rc.json
rm src/app/api.service.spec.ts src/app/cart.store.ts
show cat .config/ng-nudge/rc.json
nudge
