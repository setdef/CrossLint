# card.component.scss exists and card.component.css doesn't, so
# prefer-css-over-scss should warn. It doesn't: ng-nudge looks for the
# stylesheet relative to the working directory, not to srcDir.
show ls src/app/card
nudge
# Control: with srcDir "." the same files are found, and the warning appears.
mv src/app app
echo '{ "srcDir": "." }' > .config/ng-nudge/rc.json
sed -i.bak 's#src/\*\*/\*.ts#app/**/*.ts#' tsconfig.json && rm tsconfig.json.bak
nudge
