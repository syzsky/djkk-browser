#!/usr/bin/env bash
# 无 Gradle 构建：aapt2 + javac + d8 + zipalign + apksigner
set -euo pipefail

PKG="${PKG:-com.baidu.searchbox}"          # 车机白名单里的包名，可按需替换
APP_LABEL="${APP_LABEL:-DJKK浏览器}"
OUT=build
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"

BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
PLATFORM="$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)"
JAR="$PLATFORM/android.jar"
echo "build-tools: $BT"
echo "platform   : $PLATFORM"
echo "package    : $PKG"

rm -rf "$OUT" && mkdir -p "$OUT/classes" "$OUT/dex"

javac -source 8 -target 8 -bootclasspath "$JAR" -d "$OUT/classes" \
  $(find src -name '*.java')

find "$OUT/classes" -name '*.class' > "$OUT/classlist.txt"
"$BT/d8" --lib "$JAR" --min-api 24 --output "$OUT/dex" @"$OUT/classlist.txt"

# 用目标包名重写 manifest，保证 .MainActivity 这类别名解析成 <PKG>.MainActivity
sed "s|package=\"com.djkk.browser\"|package=\"$PKG\"|" AndroidManifest.xml > "$OUT/AndroidManifest.xml"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" \
  --manifest "$OUT/AndroidManifest.xml" \
  --min-sdk-version 24 --target-sdk-version 33

(cd "$OUT/dex" && zip -q "../base.apk" classes.dex)

"$BT/zipalign" -f 4 "$OUT/base.apk" "$OUT/aligned.apk"

if [ ! -f debug.keystore ]; then
  keytool -genkeypair -v -keystore debug.keystore -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

"$BT/apksigner" sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --out "djkk-browser-$PKG.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --print-certs "djkk-browser-$PKG.apk" | head -3
ls -l "djkk-browser-$PKG.apk"
