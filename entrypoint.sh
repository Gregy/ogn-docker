#!/bin/bash
set -e

cd /opt/rtlsdr-ogn

CONF="${1:-LKHC.conf}"

if [ ! -f "$CONF" ]; then
    echo "Config file '$CONF' not found in $(pwd)" >&2
    exit 1
fi

# ogn-rf and ogn-decode each read commands from stdin in their main loop;
# fgets() returning NULL on EOF causes the program to shut down. Feed each
# a never-closing stdin so they keep running.
./ogn-rf "$CONF" < <(sleep infinity) &
RF_PID=$!

./ogn-decode "$CONF" < <(sleep infinity) &
DECODE_PID=$!

trap 'kill -TERM $RF_PID $DECODE_PID 2>/dev/null' INT TERM

wait -n $RF_PID $DECODE_PID
EXIT=$?
kill -TERM $RF_PID $DECODE_PID 2>/dev/null || true
wait
exit $EXIT
