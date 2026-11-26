nudge
# Turning spec-exists off makes its debt entry look paid off, and the run fails.
echo '{ "rules": { "spec-exists": { "enabled": false } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/rc.json
nudge
