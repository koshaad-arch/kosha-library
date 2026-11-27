#!/bin/bash
# Runs inside the emulator job: open the app, add a PDF through the real file picker, read it.
set -x
tap() { for k in 1 2 3 4 5; do adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1; xy=$(python3 tool/tap_text.py /tmp/ui.xml "$1") && { adb shell input tap $xy; return 0; }; sleep 3; done; echo "NOT FOUND: $1"; return 1; }
adb install -r app.apk
adb push tool/sample.pdf /sdcard/Download/sample-novel.pdf
adb shell monkey -p com.koshagandhi.kosha_library -c android.intent.category.LAUNCHER 1
sleep 25
adb exec-out screencap -p > shot1-shelf.png
tap "✍ Reviews" ; sleep 3; adb exec-out screencap -p > shot2-reviews.png
tap "Read" ; sleep 4
tap "Add EPUB or PDF" ; sleep 6
adb exec-out screencap -p > shot3-picker.png
tap "sample-novel" || { tap "Downloads"; sleep 3; tap "sample-novel"; }
sleep 5
adb exec-out screencap -p > shot4-dialog.png
tap "Add & read" ; sleep 18
adb exec-out screencap -p > shot5-pdf.png
adb shell input tap 540 1200 ; sleep 3
adb exec-out screencap -p > shot6-menu.png
adb shell input tap 540 1200 ; sleep 2
adb shell input swipe 900 1200 200 1200 200 ; sleep 3
adb exec-out screencap -p > shot7-next.png
adb logcat -d | grep -iE "FATAL|E/flutter|chromium.*(Uncaught|error)" | grep -v gstatic | tail -60 > emu.log || true
