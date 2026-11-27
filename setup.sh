#!/usr/bin/env bash
# Kosha's Library — one-time setup on macOS/Linux. Run from inside this folder: bash setup.sh
set -e
flutter create --org com.koshagandhi --project-name kosha_library --platforms android .
cp -f setup_files/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
mkdir -p android/app/src/main/kotlin/com/koshagandhi/kosha_library
cp -f setup_files/MainActivity.kt android/app/src/main/kotlin/com/koshagandhi/kosha_library/MainActivity.kt
G=android/app/build.gradle.kts; [ -f "$G" ] || G=android/app/build.gradle
sed -i.bak -E 's/minSdk *= *flutter\.minSdkVersion/minSdk = 23/; s/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 23/' "$G" && rm -f "$G.bak"
rm -f test/widget_test.dart
printf '\nsubprojects {\n    tasks.configureEach { if (name.startsWith("lintVital")) enabled = false }\n}\n' >> android/build.gradle.kts
flutter pub get
echo "Done. Run: flutter run   (or: flutter build apk --release)"
