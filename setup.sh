#!/usr/bin/env bash
# Kosha's Library — one-time setup on macOS/Linux. Run from inside this folder: bash setup.sh
set -e
flutter create --org com.koshagandhi --project-name kosha_library --platforms android .
cp -f setup_files/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
G=android/app/build.gradle.kts; [ -f "$G" ] || G=android/app/build.gradle
sed -i.bak -E 's/minSdk *= *flutter\.minSdkVersion/minSdk = 23/; s/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 23/' "$G" && rm -f "$G.bak"
rm -f test/widget_test.dart
flutter pub get
echo "Done. Run: flutter run   (or: flutter build apk --release)"
