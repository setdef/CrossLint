#!/bin/sh
# Shell plugin with a post_check hook that has nothing to do with debt: it counts the violations
# left after the plugins before it (the debt plugin included) have run. Needs jq.
while IFS= read -r line; do
  printf '%s' "$line" | jq -c '
    if .method == "handshake" then
      {id, result: {protocol: 1, name: "summary"}}
    elif .method == "post_check" then
      {id, result: {excused: [], report: [
        "\(.params.violations | length) violation(s) left in \(.params.violations | map(.path) | unique | length) file(s)"
      ]}}
    else
      {id, error: {code: "unknown-method", message: .method}}
    end'
done
