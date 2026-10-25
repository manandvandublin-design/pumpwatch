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
"""
if "ACCESS_FINE_LOCATION" not in m:
    m = m.replace("<application", perms + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="PumpWatch"', m, count=1)
manifest.write_text(m)

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
print("Android project patched")
