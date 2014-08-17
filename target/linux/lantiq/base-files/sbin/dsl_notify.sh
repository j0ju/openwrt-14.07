#!/bin/sh
#
# This script is called by dsl_cpe_control whenever there is a DSL event,
# we only actually care about the DSL_INTERFACE_STATUS events as these
# tell us the line has either come up or gone down.
#
# The rest of the code is basically the same at the atm hotplug code
#

[ "$DSL_NOTIFICATION_TYPE" = "DSL_INTERFACE_STATUS" ] || exit 0

. /usr/share/libubox/jshn.sh
. /lib/functions.sh
. /lib/functions/leds.sh

include /lib/network
scan_interfaces

local default
config_load system
config_get default led_dsl default
if [ "$default" != 1 ]; then
  case "$DSL_INTERFACE_STATUS" in
    "HANDSHAKE")  led_timer dsl 500 500;;
    "TRAINING")   led_timer dsl 200 200;;
    "UP")   led_on dsl;;
    *)    led_off dsl
  esac
fi

local interfaces=`ubus list network.interface.\* | cut -d"." -f3`
local ifc
for ifc in $interfaces; do

  local up
  json_load "$(ifstatus $ifc)"
  json_get_var up up

  local auto
        config_get_bool auto "$ifc" auto 1

  local autostart
  config_get_bool autostart "$ifc" autostart 1
  [ "$autostart" = 1 ] || continue

  local proto
  json_get_var proto proto

  local is_dsl_device=no
  case "$proto" in
    pppoe ) : ;; # ok
    pppoa ) is_dsl_device=yes ;; # ok
    * ) continue ;;
  esac

  if [ "$is_dsl_device" = no ]; then
    local ifnames
    ifnames="$(uci get network."$ifc".ifnames 2> /dev/null)"
    [ -z "$ifnames" ] && ifnames="$(uci get network."$ifc".ifname 2> /dev/null)"
    [ -z "$ifnames" ] && continue

    local ifname
    for ifname in $ifnames; do
      case "$ifname" in
        nas[0-9]* | ptm[0-9]* )
          is_dsl_device=yes
          break
          ;;
      esac
    done
  fi
  [ "$is_dsl_device" = yes ] || continue

  if [ "$DSL_INTERFACE_STATUS" = "UP" ]; then
    if [ "$up" != 1 ] && [ "$auto" = 1 ]; then
      logger -t "${0##*/}[$$]" -p daemon.notice "DSL line up --> ifup $ifc"
      ( sleep 1; ifup "$ifc" ) &
    fi
  else
    if [ "$up" = 1 ] && [ "$auto" = 1 ]; then
      logger -t "${0##*/}[$$]" -p daemon.notice "DSL line down --> ifdown $ifc"
      ( sleep 1; ifdown "$ifc" ) &
    else
      if [ "$up" != 1 ] && [ "$autostart" = 1 ]; then
        #logger -t "${0##*/}[$$]" -p daemon.notice "DSL line down --> ifdown $ifc"
        ( sleep 1; ifdown "$ifc" ) &
      fi
    fi
  fi

done
