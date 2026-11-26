# A warning's heading goes to standard output and its message to standard
# error. An error's message goes to standard output.
echo '$ ng-nudge 2>/dev/null'
node "$NG_NUDGE_DIR/bin/ng-nudge" 2>/dev/null
echo '$ ng-nudge >/dev/null'
node "$NG_NUDGE_DIR/bin/ng-nudge" >/dev/null
