#!/bin/sh
# builds phonekbd-bridge.apk without gradle: javac, d8, aapt2, apksigner (debug key)
set -e
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/${BUILD_TOOLS:-36.1.0}
JAR=$SDK/platforms/${PLATFORM:-android-35}/android.jar
[ -n "$JAVA_HOME" ] || JAVA_HOME=$(ls -d "$HOME"/.local/jdk/jdk-17* | head -1)
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"
rm -rf out; mkdir -p out/classes out/dex
"$BT"/aapt2 compile --dir res -o out/res.zip
"$BT"/aapt2 link -I "$JAR" --manifest AndroidManifest.xml -o out/base.apk out/res.zip
javac -nowarn --release 11 -cp "$JAR" -d out/classes $(find src -name '*.java') 2>&1 | grep -v '^Note:' || true
[ -n "$(find out/classes -name '*.class')" ]
"$BT"/d8 --lib "$JAR" --min-api 30 --output out/dex $(find out/classes -name '*.class')
cp out/base.apk out/unsigned.apk
(cd out/dex && zip -q ../unsigned.apk classes.dex)
"$BT"/zipalign -f 4 out/unsigned.apk out/aligned.apk
"$BT"/apksigner sign --v4-signing-enabled false --ks "${KEYSTORE:-$HOME/.android/debug.keystore}" --ks-pass pass:android --out phonekbd-bridge.apk out/aligned.apk
rm -rf out
echo phonekbd-bridge.apk
