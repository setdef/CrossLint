# Three spec-exists entries: a has no comment, b and c have comments.
show cat .config/ng-nudge/debt.tsv
# Without withComment, debt is excused and never shown.
nudge
for setting in '"warning"' 'true' '"none"' '"error"' 'false' '{ "maxSeverity": "none", "matching": "^legacy" }'; do
  echo "{ \"rules\": { \"has-debt\": { \"withComment\": $setting } } }" > .config/ng-nudge/rc.json
  show cat .config/ng-nudge/rc.json
  nudge
done
echo '{ "rules": { "has-debt": { "withComment": true, "severity": "warning" } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/rc.json
nudge
