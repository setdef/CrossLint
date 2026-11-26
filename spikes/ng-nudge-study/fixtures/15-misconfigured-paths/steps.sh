# srcDir names a folder that doesn't exist: the run passes.
show cat .config/ng-nudge/rc.json
nudge
# A misspelled key is ignored without a word: the rule stays on.
echo '{ "rule": { "spec-exists": { "enabled": false } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/rc.json
nudge
# An unknown severity is ignored the same way.
echo '{ "rules": { "spec-exists": { "severity": "warn" } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/rc.json
nudge
# A misspelled flag value or flag is ignored, and warnings don't fail.
echo '{ "rules": { "spec-exists": { "severity": "warning" } } }' > .config/ng-nudge/rc.json
nudge --warnings=eror
nudge --quite
# No tsconfig.json: the run stops.
rm tsconfig.json
nudge
