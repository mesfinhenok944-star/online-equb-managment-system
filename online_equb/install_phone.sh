#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install_phone.sh — Build and install the Equb app on TECNO KN3
# Usage: bash install_phone.sh
# ─────────────────────────────────────────────────────────────────────────────

echo "🔄 Restarting ADB..."
adb kill-server
sleep 1
adb start-server
sleep 2

echo "📱 Connected devices:"
adb devices

DEVICE_ID=$(adb devices | grep "device$" | awk '{print $1}' | head -1)
if [ -z "$DEVICE_ID" ]; then
  echo ""
  echo "❌ No Android device found!"
  echo ""
  echo "Fix steps:"
  echo "  1. Connect TECNO KN3 via USB cable"
  echo "  2. Enable Developer Options: Settings → About → tap Build Number 7 times"
  echo "  3. Enable USB Debugging: Settings → Developer Options → USB Debugging ON"
  echo "  4. On phone: tap 'Allow USB Debugging' when prompted"
  echo "  5. Run this script again"
  exit 1
fi

echo ""
echo "✅ Device found: $DEVICE_ID"
echo ""
echo "🔨 Building APK..."
cd "$(dirname "$0")"
flutter build apk --debug

if [ $? -ne 0 ]; then
  echo "❌ Build failed!"
  exit 1
fi

echo ""
echo "📲 Installing on $DEVICE_ID..."
adb -s "$DEVICE_ID" install -r build/app/outputs/flutter-apk/app-debug.apk

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ SUCCESS! App installed on your TECNO KN3"
  echo "   Open 'Equb App' on your phone"
  echo ""
  # Launch the app automatically
  adb -s "$DEVICE_ID" shell monkey -p et.equb.equb_app 1 2>/dev/null || true
else
  echo "❌ Installation failed. Try unplugging and replugging USB."
fi
