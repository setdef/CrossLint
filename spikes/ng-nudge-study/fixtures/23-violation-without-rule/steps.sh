# A violation built without a rule has no rule name, so debt can't record it.
# The first run reports it. --update-debt then stops with an error and writes
# no debt file. Once the debt file has an entry, every run stops.
nudge
nudge --update-debt
show ls .config/ng-nudge
printf 'Rule\tArtifact\tComment\nspec-exists\tapp/other/other\t\n' > .config/ng-nudge/debt.tsv
nudge
