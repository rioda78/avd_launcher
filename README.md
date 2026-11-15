# AVD Launcher

Aplikasi desktop Windows untuk memilih Android Virtual Device (AVD) dan menjalankannya.

## Menjalankan

Gunakan salah satu lokasi resmi ini (keduanya menunjuk ke exe yang sama):

- pintasan `AVD Launcher.lnk` di folder utama proyek
- `build\windows\x64\runner\Release\avd_launcher.exe`

Jangan jalankan `build\windows\x64\runner\avd_launcher.exe` (tanpa folder Release). File itu adalah keluaran Ninja yang sering tidak disertai `data\app.so` dan DLL plugin terbaru, sehingga aplikasi memakai kode lama. Skrip build memindahkan file lepas itu ke `build\windows\x64\runner_stray_backup` dan memperbarui pintasan.

Tutup AVD Launcher sebelum membangun ulang, agar `avd_launcher.exe` di folder Release dapat ditimpa.

1. Pastikan Android SDK sudah terpasang. Aplikasi mencari `emulator.exe` dan `adb.exe` dari, berurutan:
   - folder yang Anda pilih secara manual (disimpan di `settings.json`, lihat di bawah)
   - `ANDROID_HOME`
   - `ANDROID_SDK_ROOT`
   - `%LOCALAPPDATA%\Android\Sdk`
2. Jalankan `avd_launcher.exe` di atas, atau dari folder proyek:

   ```bat
   flutter run -d windows --release
   ```

   `flutter run` memerlukan instalasi Visual Studio yang lengkap (lihat bagian Membangun).

Emulator dijalankan terpisah dari aplikasi. Menutup AVD Launcher tidak menghentikan emulator yang sudah mulai.

Saat Mulai, aplikasi menjalankan `emulator.exe` (bukan qemu secara langsung) dari folder `SDK\emulator`, meneruskan `ANDROID_SDK_ROOT`, `ANDROID_HOME`, dan `ANDROID_AVD_HOME`, menyembunyikan jendela konsol, dan menulis log ke folder pengaturan. Daftar perangkat dipantau lewat `adb devices` sampai emulator tampil atau prosesnya berhenti. Jika system image AVD tidak ada, pesan kesalahan ditampilkan tanpa menunggu, beserta contoh perintah `sdkmanager` untuk memasangnya (perintah itu tidak dijalankan otomatis).

Pengaturan (misalnya folder SDK manual) disimpan ke `settings.json` pada lokasi pertama yang dapat ditulisi, berurutan:

- direktori dukungan aplikasi (`path_provider`)
- `%LOCALAPPDATA%\AVD Launcher`
- folder yang sama dengan `avd_launcher.exe` (portabel)

Jika sebuah berkas sudah ada di salah satu lokasi itu, atau di lokasi lama `%APPDATA%\AVD Launcher`, aplikasi membacanya dari sana. Jalur berkas yang dipakai ditampilkan di jendela aplikasi.

## Fitur

- **Antarmuka Multi-Tab & Panel Log di Sisi Kanan**:
  - Tab **Virtual Device** dan **Perangkat ADB & SDK** di sisi kiri.
  - **Panel Log** permanen di sebelah kanan dengan dua sub-tab: **Log Emulator** (menampilkan isi log proses `emulator-<nama>.log` secara langsung) dan **Log Aktivitas** (riwayat semua aksi, status, dan galat dengan cap waktu), lengkap dengan tombol muat ulang, salin ke clipboard, bersihkan log, dan buka di Notepad.
- Daftar AVD dengan tombol Segarkan, menampilkan ringkasan spesifikasi (API, tag, ABI, RAM, penyimpanan), indikator status "Berjalan", dan peringatan jika system image hilang
- **Unduh & Pasang Android SDK Otomatis**: Jika Android SDK atau komponennya belum ditemukan, tersedia tombol **Unduh & Pasang SDK Otomatis…** (atau **Unduh komponen SDK…**) yang secara otomatis mengunduh Android Command-line Tools dari Google, mengekstrak, menyetujui lisensi SDK, dan menginstal `platform-tools` (`adb.exe`), `emulator`, `platforms`, serta `system-images`
- Deteksi folder `.avd` yatim (tanpa berkas `.ini` pasangan) di `ANDROID_AVD_HOME` beserta tombol **Bersihkan**
- Pembersihan otomatis berkas/direktori kunci yang tertinggal (`hardware-qemu.ini.lock`, `multiinstance.lock`, `userdata-qemu.img.lock`, dan sejenisnya) dengan cadangan berstempel waktu di folder `lock-backup-YYYYMMDD-HHMMSS` di dalam `.avd`, plus `bootcompleted.ini` dan `snapshot.trace`, serta menyalakan daemon ADB (`adb start-server`) sebelum emulator diluncurkan agar emulator tidak tertahan saat startup
- Mulai AVD yang dipilih, tanpa jendela konsol qemu, serta melacak nomor seri emulator baru saat lebih dari satu emulator dijalankan
- Tombol **Hentikan proses macet** untuk mematikan proses `emulator.exe`/`qemu-system-x86_64.exe` milik AVD yang sama jika tidak ada jendela perangkat dan port adb 5554/5555 tidak terbuka, lalu membersihkan kunci yatim (dengan cadangan). Jika proses macet atau snapshot quickboot `default_boot` tampak tidak lengkap (misalnya `ram.img.dirty` atau `snapshot.pb` terlalu kecil), aplikasi menyarankan **Boot dingin** (`-no-snapshot-load`). Snapshot tidak dihapus otomatis.
- Opsi boot dingin (`-no-snapshot-load`), hapus data (`-wipe-data`, dengan konfirmasi), tanpa audio (`-no-audio`), dan mode GPU (`-gpu auto|host|swiftshader_indirect`, atau memakai nilai di config AVD). Preferensi pilihan AVD terakhir dan opsi jalankan disimpan otomatis di `settings.json`
- Edit AVD: system image, RAM, penyimpanan internal, mode GPU, dan inti CPU. `config.ini` dicadangkan dengan cap waktu sebelum disimpan. AVD yang sedang berjalan tidak dapat diedit.
- Buat AVD baru lewat `avdmanager` dan Hapus AVD (menjalankan `avdmanager delete avd` sekaligus membersihkan langsung berkas `<nama>.ini` dan folder `<nama>.avd` agar AVD yang system image-nya hilang pun tetap terhapus bersih)
- Pintasan untuk membuka folder `.avd` di Explorer dan membuka log emulator terakhir di Notepad
- Daftar perangkat `adb devices -l` beserta nama AVD aslinya, tombol **Pasang APK** (`adb install -r`), tombol **Restart ADB**, dan **Hentikan** untuk emulator (`adb -s emulator-XXXX emu kill`)
- Pesan kesalahan yang jelas jika SDK atau emulator tidak ditemukan

Antarmuka memakai bahasa Indonesia.

## Tes

```bat
flutter test
```

## Membangun dari sumber

Diperlukan Flutter (channel stable) serta MSVC, CMake, Ninja, dan Windows SDK.

`flutter build windows --release` akan gagal jika Visual Studio tercatat tidak lengkap (misalnya pembaruan yang dibatalkan, sehingga `isComplete`/`isLaunchable` bernilai false). Di mesin itu, gunakan:

```bat
build_windows_release.bat
```

Hasilnya ada di `build\windows\x64\runner\Release\avd_launcher.exe`.

Jika Visual Studio sudah diperbaiki (beban kerja "Desktop development with C++") dan `flutter doctor` tidak lagi menandai masalah itu, `flutter build windows --release` adalah cara yang disarankan.

## Batasan

- Hanya mendukung Windows, karena path yang dicari adalah `emulator.exe` dan `adb.exe`.
- Perangkat fisik yang terlihat di adb ditampilkan, tetapi tidak dapat dihentikan dari aplikasi ini.
- Folder AVD yang tidak lengkap (ada direktori `.avd` tanpa file `.ini` yang sesuai) tidak muncul di `emulator -list-avds`, jadi juga tidak muncul di daftar aplikasi.
