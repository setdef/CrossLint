# The spec now exists, so the one debt entry is stale.
nudge
# --update-debt removes the entry, then still tells you to run
# --update-debt, and still exits 1.
nudge --update-debt
# With no entries left, the file has lost its header row.
show od -c .config/ng-nudge/debt.tsv
nudge
