# A syntax error in rc.json ends in an uncaught exception and a stack trace,
# with the same exit status as a violation.
nudge > out.txt 2>&1
sed -n '1,6p' out.txt
echo '...'
tail -n 1 out.txt
