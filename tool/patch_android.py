"""Adjusts the Android project that `flutter create` generates (run in CI).

- app name, permissions
- minSdk 24 (needed by Firebase and ML Kit)
- release signing from the upload keystore when the CI secrets are set
"""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent

manifest = root / "android/app/src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <uses-feature android:name="android.hardware.usb.host" android:required="false"/>
"""
if "ACCESS_FINE_LOCATION" not in m:
    m = m.replace("<application", perms + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="PumpWatch"', m, count=1)
if "supportsPictureInPicture" not in m:
    # floating window (picture-in-picture) for Dashcam mode
    m = m.replace("<activity", '<activity\n            android:supportsPictureInPicture="true"', 1)
if "USB_DEVICE_ATTACHED" not in m:
    # Offer "Open PumpWatch when this USB camera is connected" so Android remembers the USB permission
    filt = """            <intent-filter>
                <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
            </intent-filter>
            <meta-data
                android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
                android:resource="@xml/device_filter" />
"""
    i = m.index("</activity>")
    m = m[:i] + filt + "        " + m[i:]
manifest.write_text(m)
import shutil as _sh
xml_dir = root / "android/app/src/main/res/xml"
xml_dir.mkdir(parents=True, exist_ok=True)
_sh.copy(root / "tool/res/xml/device_filter.xml", xml_dir / "device_filter.xml")

# JitPack hosts the USB camera library
top = root / "android/build.gradle.kts"
t = top.read_text()
if "jitpack.io" not in t:
    t = t.replace("mavenCentral()", 'mavenCentral()\n        maven { url = uri("https://jitpack.io") }')
    top.write_text(t)
assert "jitpack.io" in t, "jitpack not added"
if "constraint-layout" not in t:
    # flutter_uvc_camera asks for a misspelt "constraint-layout: 5.0.0"; use the real AndroidX package instead
    t += """
subprojects {
    configurations.all {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.android.support.constraint:constraint-layout"))
                .using(module("androidx.constraintlayout:constraintlayout:2.1.4"))
        }
    }
}
"""
    top.write_text(t)
settings = root / "android/settings.gradle.kts"
st = settings.read_text()
if "jitpack.io" not in st and "dependencyResolutionManagement" in st:
    st = st.replace("mavenCentral()", 'mavenCentral()\n        maven { url = uri("https://jitpack.io") }')
    settings.write_text(st)

gradle = root / "android/app/build.gradle.kts"
g = gradle.read_text()
g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", g)

signing = '''
    signingConfigs {
        create("release") {
            val ks = System.getenv("PW_KEYSTORE_PATH")
            if (ks != null && file(ks).exists()) {
                storeFile = file(ks)
                storePassword = System.getenv("PW_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("PW_KEY_ALIAS")
                keyPassword = System.getenv("PW_KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
if 'create("release")' not in g:
    g = g.replace("\n    buildTypes {", signing, 1)
    g = re.sub(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (System.getenv("PW_KEYSTORE_PATH") != null) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        g,
        count=1,
    )
gradle.write_text(g)
assert 'signingConfigs.getByName("release")' in g, "release signing not patched"
# ProGuard/R8 rules for release builds
import shutil
shutil.copy(root / "tool/proguard-rules.pro", root / "android/app/proguard-rules.pro")
g = gradle.read_text()
if "proguard-rules.pro" not in g:
    g = g.replace(
        'signingConfig = if (System.getenv("PW_KEYSTORE_PATH")',
        'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n'
        '            signingConfig = if (System.getenv("PW_KEYSTORE_PATH")',
        1,
    )
    gradle.write_text(g)
assert "proguard-rules.pro" in g, "proguard rules not added"
print("Android project patched")
