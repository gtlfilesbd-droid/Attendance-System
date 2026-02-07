#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "========================================================"
echo "Genesis Employee App - Release Build"
echo "========================================================"

echo ""
echo "Choose platform:"
echo "  1 = Android (signed APK)"
echo "  2 = Android (App Bundle for Play Store)"
echo "  3 = iOS (release build; then archive in Xcode)"
read -r -p "Enter 1, 2, or 3: " choice

case "$choice" in
  1)
    echo ""
    if [ ! -f android/key.properties ]; then
      echo "[WARN] android/key.properties not found. APK will be signed with debug key."
      echo "For release signing, copy android/key.properties.example to android/key.properties"
      echo "See docs/BUILD_AND_RELEASE.md"
      echo ""
    fi
    flutter build apk --release
    echo ""
    echo "[OK] APK: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  2)
    echo ""
    if [ ! -f android/key.properties ]; then
      echo "[WARN] android/key.properties not found. Bundle will be signed with debug key."
      echo "For Play Store, create android/key.properties from android/key.properties.example"
      echo "See docs/BUILD_AND_RELEASE.md"
      echo ""
    fi
    flutter build appbundle --release
    echo ""
    echo "[OK] AAB: build/app/outputs/bundle/release/app-release.aab"
    echo "Upload this file to Google Play Console."
    ;;
  3)
    echo ""
    flutter build ios --release
    echo ""
    echo "[OK] Open ios/Runner.xcworkspace in Xcode, then Product -> Archive and Distribute."
    echo "See docs/BUILD_AND_RELEASE.md for signing and App Store steps."
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac
