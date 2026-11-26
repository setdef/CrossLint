#!/bin/sh
# Misbehaving plugin for the host's error paths. $1 selects the fault.
case "$1" in
  crash)      echo "boom: something went wrong inside the plugin" >&2; exit 3 ;;
  garbage)    read -r line; echo "this is not json" ;;
  wrong-protocol) read -r line; echo '{"id":1,"result":{"protocol":2,"name":"future"}}' ;;
  error-reply) while read -r line; do
                 case "$line" in
                   *handshake*) echo '{"id":1,"result":{"protocol":1,"name":"error-reply"}}' ;;
                   *) echo '{"id":2,"error":{"code":"dependency-missing","message":"the project has no installed typescript"}}' ;;
                 esac
               done ;;
  # A plugin that starts a child and hangs. The child's pid goes to $HANG_PIDFILE so run.sh can check it is gone.
  hang)       read -r line; sleep 30 & echo $! > "$HANG_PIDFILE"; wait ;;
esac
