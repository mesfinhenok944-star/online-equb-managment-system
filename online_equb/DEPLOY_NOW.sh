#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY_NOW.sh — Complete deployment script for Online Equb
# Run this script from your terminal to deploy everything
# ─────────────────────────────────────────────────────────────────────────────

set -e
cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      Online Equb — Full Deployment           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Build Flutter Web ────────────────────────────────────────────────
echo "1️⃣  Building Flutter Web App..."
flutter build web --release
echo "   ✅ Web app built: build/web/"

# ── Step 2: Deploy to Firebase Hosting ───────────────────────────────────────
echo ""
echo "2️⃣  Deploying to Firebase Hosting..."
echo "   (First time? Run: firebase login)"
firebase deploy --only hosting --project online-equb-managment-system
echo "   ✅ Web app live at: https://online-equb-managment-system.web.app"

# ── Step 3: Build Release APK ────────────────────────────────────────────────
echo ""
echo "3️⃣  Building Release APK for Android..."
flutter build apk --release
echo "   ✅ APK built: build/app/outputs/flutter-apk/app-release.apk"

# ── Step 4: Install on phone (if connected) ───────────────────────────────────
echo ""
echo "4️⃣  Installing APK on connected phone..."
adb kill-server && sleep 1 && adb start-server && sleep 2
DEVICE=$(adb devices | grep "device$" | awk '{print $1}' | head -1)
if [ -n "$DEVICE" ]; then
  adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-release.apk
  echo "   ✅ Installed on device: $DEVICE"
else
  echo "   ⚠️  No phone connected. Install manually:"
  echo "      adb install -r build/app/outputs/flutter-apk/app-release.apk"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ DEPLOYMENT COMPLETE!                                     ║"
echo "║                                                              ║"
echo "║  Web:    https://online-equb-managment-system.web.app       ║"
echo "║  APK:    build/app/outputs/flutter-apk/app-release.apk      ║"
echo "║  GitHub: https://github.com/mesfinhenok944-star/...         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
