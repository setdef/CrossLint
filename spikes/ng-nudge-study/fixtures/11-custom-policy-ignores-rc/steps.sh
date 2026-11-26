# Custom policies run. rc.json makes readme-exists a warning, but ng-nudge
# constructs each custom policy with no arguments, so the rule never sees
# the config and stays an error. "enabled": false is ignored the same way.
show cat .config/ng-nudge/rc.json
nudge
echo '{ "rules": { "readme-exists": { "enabled": false } } }' > .config/ng-nudge/rc.json
nudge
