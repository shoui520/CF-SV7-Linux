#!/bin/bash
# letsnote-wireless-switch.sh
# Wireless switch daemon for Panasonic Let's Note CF-SV series on Linux
# Reads EC register 0xA6 bit 0 for switch state, listens to journald for toggle events

EC_IO="/sys/kernel/debug/ec/ec0/io"
EC_OFFSET=$((0xA6))

read_switch() {
    local val
    val=$(dd if="$EC_IO" bs=1 skip="$EC_OFFSET" count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
    echo $(( val & 1 ))
}

apply_state() {
    local state
    state=$(read_switch)
    if [[ "$state" == "1" ]]; then
        rfkill unblock wlan
        echo "Wireless switch ON — wlan unblocked"
    else
        rfkill block wlan
        echo "Wireless switch OFF — wlan blocked"
    fi
}

# Apply state immediately at startup
apply_state

# Watch journald for the hotkey event, apply state on each toggle
journalctl -k -f --no-pager -g "Unknown hotkey event: 0x0050" | while read -r _; do
    apply_state
done
