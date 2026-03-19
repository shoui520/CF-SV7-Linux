#!/bin/sh
profiles=$(autorandr --list 2>/dev/null)

if [ -z "$profiles" ]; then
    notify-send -a "画面設定の復元" "保存したautorandrプロファイルはありません。" \
        "autorandr --save <名前>でディスプレイ設定を保存してから、また試してください。"
    exit 1
fi

choice=$(echo "$profiles" | kdialog --menu "保存したプロファイルを読み込みます" \
    $(echo "$profiles" | awk '{print $1, $1}') \
    --title "画面設定の復元" 2>/dev/null)

# user cancelled
[ -z "$choice" ] && exit 0

output=$(autorandr --load "$choice" --force 2>&1)

if [ $? -eq 0 ]; then
    notify-send -a "画面設定の復元" "ディスプレイ設定を復元しました" "現在のプロファイル: $choice"
else
    notify-send -a "画面設定の復元" "プロファイルの読み込みに失敗しました。" "$output"
fi
