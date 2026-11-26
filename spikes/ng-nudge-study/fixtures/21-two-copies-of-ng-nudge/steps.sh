# Fixture 19 again, but the project's node_modules holds a copy of ng-nudge
# rather than the one that runs, as with a global install or a second
# version. HasSpec compares companion classes by identity, so the page's
# Spec class is not ng-nudge's, and the page is not checked.
rm node_modules/@overthetopmarketing/ng-nudge
cp -R "$NG_NUDGE_DIR" node_modules/@overthetopmarketing/ng-nudge
nudge
