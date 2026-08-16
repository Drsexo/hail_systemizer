#!/system/bin/sh

SKIPUNZIP=0

ui_print " "
ui_print "=================================="
ui_print "  Hail Systemizer"
ui_print "  privileged system app installer"
ui_print "=================================="
ui_print " "

APK="$MODPATH/system/priv-app/Hail/Hail.apk"
if [ ! -f "$APK" ]; then
    abort "Hail.apk missing from module zip. Refusing to install."
fi

APK_SIZE=$(stat -c %s "$APK" 2>/dev/null || wc -c < "$APK")
if [ "$APK_SIZE" -lt 100000 ]; then
    ui_print "! WARNING: Hail.apk looks small ($APK_SIZE bytes)."
fi
ui_print "- Hail.apk present ($APK_SIZE bytes)"

USER_APK=$(pm path com.aistra.hail 2>/dev/null | head -n1 | sed 's/^package://')
case "$USER_APK" in
    /data/*)
        ui_print "- User-space Hail detected, uninstalling..."
        pm uninstall com.aistra.hail >/dev/null 2>&1
        ui_print "  Done."
        ;;
esac

set_perm_recursive "$MODPATH/system/priv-app"          0 0 0755 0644
set_perm_recursive "$MODPATH/system/etc/permissions"   0 0 0755 0644

chcon u:object_r:system_file:s0 "$MODPATH/system/priv-app/Hail/Hail.apk" 2>/dev/null
chcon u:object_r:system_file:s0 "$MODPATH/system/etc/permissions/privapp-permissions-com.aistra.hail.xml" 2>/dev/null

ui_print " "
ui_print "- Done. Reboot to activate."
ui_print "  Open Hail, Working Mode, Privileged System App."
ui_print " "