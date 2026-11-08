# TurnBridge

Navigasi Apple Maps (MapKit) → notifikasi lokal → Huawei Watch Fit 3.

TurnBridge menghitung rute memakai data Apple Maps, lalu mengirim notifikasi tiap
mendekati belokan. iPhone terkunci → iOS meneruskan notifikasi lewat ANCS → Huawei
Health → jam bergetar dan menampilkan teks arah.

Tidak ada server, tidak ada akun, tidak ada data keluar dari HP.

## Cara kerja

1. `MKDirections` menghasilkan `MKRoute` berisi langkah belokan.
2. `CLLocationManager` berjalan di background (mode `location`).
3. Jarak ke titik belokan < radius (mobil 170 m, jalan 45 m) → `UNNotificationRequest`.
4. Notifikasi itu yang muncul di jam (Huawei Health > Notifikasi > TurnBridge).

## Syarat di iPhone

- iOS 16+
- Huawei Health: `Perangkat > Watch Fit 3 > Notifikasi > TurnBridge` ON
- iPhone: `Pengaturan > Bluetooth > (i) Watch Fit 3 > Share System Notifications` ON
- Aplikasi: Lokasi **Selalu**, Notifikasi diizinkan

## Ambil tujuan dari Apple Maps

1. Apple Maps: cari tempat → ketuk → **Bagikan** → **Salin**.
2. Buka TurnBridge → **Tempel**. Rute langsung dihitung.
3. Kalau muncul dialog *Allow Paste*, pilih **Allow**.

Yang dikenali: link `maps.apple.com/place?...&coordinate=..&name=..` (format Share iOS 16+),
teks share multi-baris, `maps.apple.com/?q=..&ll=..`, `?daddr=..`, link
`google.com/maps/place/Nama/@lat,lon,17z`, link pendek `maps.app.goo.gl/..`
(diikuti redirect-nya), `comgooglemaps://?daddr=..`, `lat,lon`, atau nama tempat saja.

Kalau clipboard tidak terbaca, aplikasi membuka **sheet tempel manual** berisi teks mentah
clipboard — tempel/rapikan di situ lalu tekan **Mulai Navigasi**.

## Kalau rute tidak muncul

Kartu **DIAGNOSA** di bawah layar mencatat: isi clipboard, link yang dipakai, hasil parsing,
dan jawaban MapKit. Tekan **Salin log** lalu kirim isinya.

Penyebab yang sudah ditangani otomatis:

- GPS belum dapat titik (baru buka app) → minta satu lokasi lalu hitung ulang.
- Titik tujuan tidak bisa dirutekan (pin di tengah gedung) → dicari ulang lewat MKLocalSearch.
- Link `?daddr=Nama`, `?query=..`, `maps.apple.com/directions?destination=..` → dikenali.

## Build

### A. GitHub Actions (tanpa Xcode)

1. Buat repo kosong `TurnBridge` di GitHub, lalu:
   ```
   git remote add origin git@github.com:<user>/TurnBridge.git
   git add -A && git commit -m "TurnBridge" && git push -u origin main
   ```
2. Tab **Actions** → workflow *Build TurnBridge IPA* → **Run workflow**.
3. Unduh artifact `TurnBridge-unsigned-ipa`, ekstrak `TurnBridge.ipa`.

### B. Xcode lokal

```
brew install xcodegen
xcodegen generate
open TurnBridge.xcodeproj
```

Pilih iPhone sebagai target, isi Team dengan Apple ID, Run.

## Pasang di iPhone (unsigned IPA)

1. `brew install --cask altstore`, buka AltServer dari menu bar.
2. AltServer > Install AltStore > pilih iPhone (sambungkan kabel, Apple ID gratis).
3. Kirim `TurnBridge.ipa` ke iPhone (AirDrop/Files), buka di AltStore, Sign In, Install.
4. `Pengaturan > Umum > VPN & Device Management` > trust developer.
5. Buka TurnBridge:
   - izinkan Notifikasi
   - izinkan Lokasi → pilih **Always**
   - tekan **Tes Notifikasi**, kunci iPhone, cek jam
6. Huawei Health > Perangkat > Notifikasi > aktifkan **TurnBridge**.

Apple ID gratis: app berlaku 7 hari, maksimal 3 app. Perpanjang lewat AltStore
(Refresh) selama AltServer bisa dijangkau.

## Batasan

- Ini bukan UI Petal Maps di jam; yang tampil teks arah sebagai notifikasi.
- Belokan dihitung dari jarak lurus ke titik maneuver, bukan progres sepanjang rute.
- Rute ulang otomatis belum ada: hentikan lalu mulai lagi kalau keluar jalur.
