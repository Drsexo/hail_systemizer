#!/system/bin/sh
#
# Boots-time hook. Detects a stale user-space Hail install shadowing
# our /system/priv-app copy and leaves a marker file the user can check.
#

USER_APK=$(pm path com.aistra.hail 2>/dev/null | head -n1 | sed 's/^package://')
if [ -z "$USER_APK" ] || [ ! -f "$USER_APK" ]; then
    exit 0
fi

case "$USER_APK" in
    /data/*)
        mkdir -p /data/local/tmp
        {
            echo "Hail Systemizer: user-space Hail detected at:"
            echo "  $USER_APK"
            echo "Run: pm uninstall com.aistra.hail"
            echo "Timestamp: $(date)"
        } > /data/local/tmp/hail_systemizer_warning.txt
        ;;
esac
