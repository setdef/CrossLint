# With --warnings=error a warning fails the run, but the output still marks
# it as a warning, and with --quiet it is not printed at all: the run exits 1
# with no output. The api service has no spec file, and spec-exists is a
# warning in rc.json.
nudge --warnings=error
nudge --warnings=error --quiet
