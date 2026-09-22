#!/usr/bin/env bash
set -euo pipefail

# patch-navbar.sh
# Applies navigation bar modifications to siyuan-android using awk pattern-matching
# rather than fragile unified diff line offsets.
#
# Usage:
#   ./patch-navbar.sh [path-to-siyuan-android]
# If path is omitted, defaults to the current working directory.

TARGET_DIR="${1:-.}"
SIYUAN_JAVA_DIR="$TARGET_DIR/app/src/main/java/org/b3log/siyuan"

if [ ! -d "$SIYUAN_JAVA_DIR" ]; then
    echo "ERROR: SiYuan Java directory not found at '$SIYUAN_JAVA_DIR'" >&2
    exit 1
fi

echo "==> Patching siyuan-android navbar handling in: $TARGET_DIR"

# 1. Remove all invocations of BarUtils.setNavBarVisibility(..., false)
echo "--> Removing BarUtils.setNavBarVisibility invocations..."
find "$SIYUAN_JAVA_DIR" -maxdepth 1 -name "*.java" -type f | sort | while read -r file; do
    if grep -q "BarUtils\.setNavBarVisibility" "$file"; then
        awk '!/BarUtils\.setNavBarVisibility/' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        echo "    ✓ Removed from $(basename "$file")"
    fi
done

# 2. ShortcutActivity.java: ensure AndroidBug5497Workaround is NOT called
# ShortcutActivity uses a native LinearLayout root view with adjustResize; calling
# AndroidBug5497Workaround causes a ClassCastException (LinearLayout cannot be cast to FrameLayout).
SHORTCUT_ACTIVITY="$SIYUAN_JAVA_DIR/ShortcutActivity.java"
if [ -f "$SHORTCUT_ACTIVITY" ]; then
    if grep -q "AndroidBug5497Workaround.assistActivity" "$SHORTCUT_ACTIVITY"; then
        echo "--> Removing incompatible AndroidBug5497Workaround from ShortcutActivity.java..."
        awk '!/AndroidBug5497Workaround\.assistActivity/ && !/\/\/ 系统导航栏与软键盘遮挡处理/' "$SHORTCUT_ACTIVITY" > "$SHORTCUT_ACTIVITY.tmp" && mv "$SHORTCUT_ACTIVITY.tmp" "$SHORTCUT_ACTIVITY"
        echo "    ✓ Removed AndroidBug5497Workaround from ShortcutActivity.java"
    fi
fi

# 3. JSAndroid.java: ensure webView parent background color is set
JS_ANDROID="$SIYUAN_JAVA_DIR/JSAndroid.java"
if [ -f "$JS_ANDROID" ]; then
    echo "--> Ensuring webView parent background color in JSAndroid.java..."
    if ! grep -q "webView.getParent()).setBackgroundColor" "$JS_ANDROID"; then
        awk '
        {
            print $0
            if ($0 ~ /UltimateBarX\.statusBarOnly\(activity\)/) {
                print "            ((android.view.View) activity.webView.getParent()).setBackgroundColor(colorVal);"
            }
        }' "$JS_ANDROID" > "$JS_ANDROID.tmp" && mv "$JS_ANDROID.tmp" "$JS_ANDROID"
        echo "    ✓ Added webView parent background color to JSAndroid.java"
    else
        echo "    - webView parent background color already present in JSAndroid.java"
    fi
fi

# 4. AndroidBug5497Workaround.java: add navigationBars insets padding
WORKAROUND="$SIYUAN_JAVA_DIR/AndroidBug5497Workaround.java"
if [ -f "$WORKAROUND" ]; then
    echo "--> Ensuring navigationBars insets handling in AndroidBug5497Workaround.java..."
    if ! grep -q "Type\.navigationBars()" "$WORKAROUND"; then
        awk '
        {
            # Modern branch (Android 12L+ / S_V2): registerKeyboardInsets()
            if ($0 ~ /currentInsets\[0\] = insets;/) {
                print "            final int imeHeight = insets.getInsets(WindowInsets.Type.ime()).bottom;"
                print "            final android.graphics.Insets navBars = insets.getInsets(android.view.WindowInsets.Type.navigationBars());"
                print "            v.setPadding(navBars.left, v.getPaddingTop(), navBars.right, imeHeight > 0 ? 0 : navBars.bottom);"
            }

            print $0

            # Fallback / older branch (Android R to S):
            if ($0 ~ /imeHeight = insets\.getInsets\(.*Type\.ime\(\)\)\.bottom;/) {
                print ""
                print "                // 保持系统导航栏可见时通过内边距避免内容被遮挡；"
                print "                // 键盘弹出时 IME 高度已包含导航栏区域（视图底部即键盘顶部），底部内边距置 0 避免重复计算"
                print "                final android.graphics.Insets navBars = insets.getInsets(android.view.WindowInsets.Type.navigationBars());"
                print "                v.setPadding(navBars.left, v.getPaddingTop(), navBars.right, imeHeight > 0 ? 0 : navBars.bottom);"
            }
        }' "$WORKAROUND" > "$WORKAROUND.tmp" && mv "$WORKAROUND.tmp" "$WORKAROUND"
        echo "    ✓ Added navigationBars padding to AndroidBug5497Workaround.java"
    else
        echo "    - navigationBars insets handling already present in AndroidBug5497Workaround.java"
    fi
fi

# 5. shortcuts.xml: update targetPackage to match debug package name
SHORTCUTS_XML="$TARGET_DIR/app/src/main/res/xml/shortcuts.xml"
if [ -f "$SHORTCUTS_XML" ]; then
    echo "--> Ensuring debug targetPackage in shortcuts.xml..."
    if grep -q 'android:targetPackage="org\.b3log\.siyuan"' "$SHORTCUTS_XML"; then
        awk '{gsub(/android:targetPackage="org\.b3log\.siyuan"/, "android:targetPackage=\"org.b3log.siyuan.debug\""); print}' "$SHORTCUTS_XML" > "$SHORTCUTS_XML.tmp" && mv "$SHORTCUTS_XML.tmp" "$SHORTCUTS_XML"
        echo "    ✓ Updated targetPackage to org.b3log.siyuan.debug in shortcuts.xml"
    else
        echo "    - targetPackage already up to date in shortcuts.xml"
    fi
fi

echo "==> Successfully applied modifications."
