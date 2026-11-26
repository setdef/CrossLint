nudge
# Two violations of one rule on one artifact become two identical rows.
nudge --update-debt
show cat .config/ng-nudge/debt.tsv
# A third input added later is a new violation, and the debt excuses it.
sed -i.bak 's#  age = input<number>();#  age = input<number>();\
  email = input<string>();#' src/app/profile/profile.component.ts && rm src/app/profile/profile.component.ts.bak
show cat src/app/profile/profile.component.ts
nudge
