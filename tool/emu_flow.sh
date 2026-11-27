#!/bin/bash
# Runs inside the emulator job: open the app, add a PDF through the real file picker, read it.
set -x
tap() { for k in 1 2 3 4 5; do adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1; xy=$(python3 tool/tap_text.py /tmp/ui.xml "$1") && { adb shell input tap $xy; return 0; }; sleep 3; done; echo "NOT FOUND: $1"; return 1; }
adb install -r app.apk
adb push tool/sample.pdf /sdcard/Download/sample-novel.pdf
adb push tool/sample_library.csv /sdcard/Download/my-library.csv
adb push tool/My_Clippings.txt /sdcard/Download/My_Clippings.txt
adb shell monkey -p com.koshagandhi.kosha_library -c android.intent.category.LAUNCHER 1
sleep 25
adb exec-out screencap -p > shot1-welcome.png
tap "Upload a CSV or Excel list" ; sleep 6
tap "my-library" || { tap "Downloads"; sleep 3; tap "my-library"; }
sleep 12
adb exec-out screencap -p > shot2-imported.png
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
# free classics: download a classic inside the app
tap "Got it" ; sleep 2
adb shell input keyevent 4 ; sleep 3
adb exec-out screencap -p > shot7b-back.png
tap "Free classics" ; sleep 6
adb exec-out screencap -p > shot8-classics.png
tap "Get" ; sleep 70
adb exec-out screencap -p > shot9-classic-open.png
adb logcat -d | grep -iE "FATAL|E/flutter" | grep -v gstatic | tail -30 >> emu.log || true
# Kindle highlights import from Settings
tap "Got it" ; sleep 1
adb shell input keyevent 4 ; sleep 3
adb shell input keyevent 4 ; sleep 3
tap "Shelf" ; sleep 3
tap "Settings" ; sleep 3
for k in 1 2 3; do adb shell input swipe 540 1900 540 700 300; sleep 1; done
tap "Import Kindle highlights" ; sleep 6
tap "My_Clippings" || { tap "Downloads"; sleep 3; tap "My_Clippings"; }
sleep 6
adb exec-out screencap -p > shot10-kindle.png
adb shell input keyevent 4 ; sleep 3
tap "📱 Digital" ; sleep 3
adb exec-out screencap -p > shot11-digital.png
