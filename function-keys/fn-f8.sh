#!/bin/sh
profiles=$(autorandr --list 2>/dev/null)

if [ -z "$profiles" ]; then
    notify-send -a "Save & Load Display Settings" "No autorandr profiles found" \
        "Save one first with: autorandr --save <name>"
    exit 1
fi

choice=$(echo "$profiles" | kdialog --menu "Restore display profile" \
    $(echo "$profiles" | awk '{print $1, $1}') \
    --title "Load Display Settings" 2>/dev/null)

# user cancelled
[ -z "$choice" ] && exit 0

output=$(autorandr --load "$choice" --force 2>&1)

if [ $? -eq 0 ]; then
    notify-send -a "Load Display Settings" "Display profile restored" "Using profile: $choice"
else
    notify-send -a "Load Display Settings" "Failed to restore profile" "$output"
fi
