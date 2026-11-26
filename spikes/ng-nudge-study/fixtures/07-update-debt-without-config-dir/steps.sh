# A project that has never configured ng-nudge has no .config/ng-nudge.
# Its first --update-debt prints no results and writes no file.
nudge --update-debt
show ls -a .config 2>&1
