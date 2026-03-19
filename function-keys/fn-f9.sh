#!/bin/sh
# panasonic-fn-f9 — Battery percentage display
# Replicates the Panasonic Fn+F9 battery remaining indicator.
# Bind this to Fn+F9 in KDE Custom Shortcuts.
# Requires: notify-send

found=0

for bat in /sys/class/power_supply/BAT*; do
    [ -d "$bat" ] || continue
    found=1

    capacity=$(cat "$bat/capacity" 2>/dev/null || echo "??")
    status=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
    model=$(cat "$bat/model_name" 2>/dev/null || echo "Unknown")
    manufacturer=$(cat "$bat/manufacturer" 2>/dev/null)

    # pick an icon based on level
    if [ "$status" = "Charging" ]; then
        icon="battery-charging"
    elif [ "$capacity" -ge 80 ] 2>/dev/null; then
        icon="battery-100"
    elif [ "$capacity" -ge 50 ] 2>/dev/null; then
        icon="battery-060"
    elif [ "$capacity" -ge 20 ] 2>/dev/null; then
        icon="battery-040"
    else
        icon="battery-low"
    fi

    label="${manufacturer:+$manufacturer }$model"

    notify-send -i "$icon" -a "Battery" \
        "Battery ${capacity}% — ${status}" \
        "$label"
done

if [ "$found" -eq 0 ]; then
    notify-send -a "Battery" "No battery found" ""
fi
