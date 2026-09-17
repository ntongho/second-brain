# Real-device smoke (Android)

Chrome is not this. USB phone + API on the PC.

## 0. Icons

```bash
cd frontend
python3 tool/render_brand.py
bash tool/install_android_brand.sh
```

Uninstall **Second Brain** from the phone if an old Flutter icon is stuck, then continue.

## 1. API reachable on Wi‑Fi

PC and phone on the **same** Wi‑Fi. API already bound `0.0.0.0:8000`.

```bash
hostname -I    # Linux — pick the 192.168.x.x or 10.x
ipconfig       # Windows — IPv4
```

Phone cannot use `localhost` or `127.0.0.1` (that is the phone itself). Sign-in will say so if you forget.

## 2. Run

```bash
cd frontend
flutter devices
flutter run -d <deviceId> \
  --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000/v1
```

Emulator only: `http://10.0.2.2:8000/v1`.

## 3. Pass / fail

| # | Check |
| --- | --- |
| 1 | Home screen icon is the folded note, not the Flutter logo |
| 2 | Sign in (email). Google on Android needs an Android OAuth client + SHA-1 — skip Google this pass if it fails |
| 3 | Empty chat, sun/moon next to Library, email menu has no Theme |
| 4 | Add a short note → ask about it → citation opens it |
| 5 | Airplane mode: library still lists the note; send queues |
| 6 | Airplane off: queued send goes |

If 2 fails with connection error: PC firewall port 8000, wrong IP, or API not on `0.0.0.0`.
