#!/bin/bash
# Forensic snapshot of host + container state during lance-certo scrape window.
# Installed at /usr/local/bin/scrape-snapshot.sh; invoked by /etc/cron.d/scrape-snapshot.
# Output appends to /var/log/scrape-monitor/YYYYMMDD.log.
#
# Temporary capture mechanism — to be replaced by sentinel's S4 (per-process top-N
# in the 24h rolling history) once that ships.

set -u

LOGDIR="/var/log/scrape-monitor"
LOGFILE="${LOGDIR}/$(date -u +%Y%m%d).log"

mkdir -p "$LOGDIR"

{
  echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) ===="
  echo "---- top -bn1 ----"
  top -bn1 | head -25
  echo "---- free -h ----"
  free -h
  echo "---- docker stats ----"
  docker stats --no-stream
  echo "---- top 20 procs by cpu ----"
  ps -eo pid,pcpu,pmem,rss,comm --sort=-pcpu | head -20
  echo
} >> "$LOGFILE" 2>&1
