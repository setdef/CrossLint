# The debt entry carries a comment. With spec-exists turned off, the entry
# looks paid off, so --update-debt deletes it and its comment.
printf 'Rule\tArtifact\tComment\nspec-exists\tapp/api/api\tlegacy, refactor planned\n' > .config/ng-nudge/debt.tsv
echo '{ "rules": { "spec-exists": { "enabled": false } } }' > .config/ng-nudge/rc.json
show cat .config/ng-nudge/debt.tsv
nudge --update-debt
show cat .config/ng-nudge/debt.tsv
