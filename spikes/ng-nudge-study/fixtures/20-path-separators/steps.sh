# Run on Windows and on macOS or Linux to compare. The Artifact column holds
# whatever separator glob returns on the system that ran --update-debt.
nudge --update-debt
show cat .config/ng-nudge/debt.tsv
# A debt file written on macOS or Linux, as a teammate would commit it:
printf 'Rule\tArtifact\tComment\nspec-exists\tapp/api/api\t\n' > .config/ng-nudge/debt.tsv
show cat .config/ng-nudge/debt.tsv
nudge
