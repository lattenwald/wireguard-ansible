#!/bin/bash

svc=${1:-unknown}

log=$(systemctl status -l -n 10 $svc)
/usr/local/bin/tgnotify -m HTML "<pre>$log</pre>"
