# PumpWatch

Petrol and diesel prices in Ireland, reported by drivers. Snap the price sign, the phone reads the price, everyone sees it on the map.

## Test server (on your PC)

Needs Python 3.8 or newer (python.org). No extra packages.

```
cd server
python server.py --demo
```

`--demo` adds 4 demo stations around Dublin city centre so the map isn't empty. Leave it off for real use.

The server prints an address like `http://192.168.1.20:8080`. Enter it in the app under **Settings › Server address**. Your phone must be on the same Wi-Fi as the PC. If Windows asks about the firewall, allow access on private networks.

Optional: put your Bee Maps key (the base64 `username:key` string) in `server/beemaps_key.txt` to enable "Check Hivemapper coverage here". Never commit that file.

## App

Flutter, Android. GitHub Actions builds the APK on every push to `main` and attaches it to a release.
