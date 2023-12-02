#!/bin/sh

now=$(date "+%Y-%m-%dT%H-%M-%S")

mv /opt/bongo/logs/a516f07394/main.log  /opt/bongo/logs/a516f07394/main.log.$now
gzip /opt/bongo/logs/a516f07394/main.log.$now &

/opt/bingo/bingo run_server
