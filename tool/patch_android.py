"""Adjusts the Android project that `flutter create` generates (run in CI)."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
manifest = root / "android/app/src/main/AndroidManifest.xml"
m = manifest.read_text()

perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
"""
if "ACCESS_FINE_LOCATION" not in m:
    m = m.replace("<application", perms + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="PumpWatch"', m, count=1)
if "usesCleartextTraffic" not in m:
    # the test server on your PC uses plain http on the local Wi-Fi
    m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
manifest.write_text(m)

for name in ("build.gradle.kts", "build.gradle"):
    g = root / "android/app" / name
    if g.exists():
        t = g.read_text()
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
        g.write_text(t)
print("Android project patched")
