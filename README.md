# AVD Launcher

Aplikasi desktop Windows untuk memilih Android Virtual Device (AVD) dan menjalankannya.

## Menjalankan

Gunakan salah satu lokasi resmi ini (keduanya menunjuk ke exe yang sama):

- pintasan `AVD Launcher.lnk` di folder proyek `E:\proyek\avd_launcher`
- `E:\proyek\avd_launcher\build\windows\x64\runner\Release\avd_launcher.exe`

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

- Daftar AVD dengan tombol Segarkan, menampilkan ringkasan spesifikasi (API, tag, ABI, RAM, penyimpanan), indikator status "Berjalan", dan peringatan jika system image hilang
- **Unduh & Pasang Android SDK Otomatis**: Jika Android SDK atau komponennya belum ditemukan, tersedia tombol **Unduh & Pasang SDK Otomatis…** (atau **Unduh komponen SDK…**) yang secara otomatis mengunduh Android Command-line Tools dari Google, mengekstrak, menyetujui lisensi SDK, dan menginstal `platform-tools` (`adb.exe`), `emulator`, `platforms`, serta `system-images`
- Deteksi folder `.avd` yatim (tanpa berkas `.ini` pasangan) di `ANDROID_AVD_HOME`
- Pembersihan otomatis berkas kunci/status yang tertinggal (`hardware-qemu.ini.lock`, `multiinstance.lock`, `bootcompleted.ini`, `snapshot.trace`) serta menyalakan daemon ADB (`adb start-server`) sebelum emulator diluncurkan agar emulator tidak tertahan saat startup
- Mulai AVD yang dipilih, tanpa jendela konsol qemu, serta melacak nomor seri emulator baru saat lebih dari satu emulator dijalankan
- Opsi boot dingin (`-no-snapshot-load`), hapus data (`-wipe-data`, dengan konfirmasi), tanpa audio (`-no-audio`), dan mode GPU (`-gpu auto|host|swiftshader_indirect`, atau memakai nilai di config AVD). Preferensi pilihan AVD terakhir dan opsi jalankan disimpan otomatis di `settings.json`
- Edit AVD: system image, RAM, penyimpanan internal, mode GPU, dan inti CPU. `config.ini` dicadangkan dengan cap waktu sebelum disimpan. AVD yang sedang berjalan tidak dapat diedit.
- Buat AVD baru dan Hapus AVD lewat `avdmanager`
- Pintasan untuk membuka folder `.avd` di Explorer dan membuka log emulator terakhir di Notepad
- Daftar perangkat `adb devices -l` beserta nama AVD aslinya, tombol **Pasang APK** (`adb install -r`), tombol **Restart ADB**, dan **Hentikan** untuk emulator (`adb -s emulator-XXXX emu kill`)
- Pesan kesalahan yang jelas jika SDK atau emulator tidak ditemukan

Antarmuka memakai bahasa Indonesia.

## Tes

```bat
cd /d E:\proyek\avd_launcher
flutter test
```

## Membangun dari sumber

Diperlukan Flutter (channel stable) serta MSVC, CMake, Ninja, dan Windows SDK.

`flutter build windows --release` akan gagal jika Visual Studio tercatat tidak lengkap (misalnya pembaruan yang dibatalkan, sehingga `isComplete`/`isLaunchable` bernilai false). Di mesin itu, gunakan:

```bat
cd /d E:\proyek\avd_launcher
build_windows_release.bat
```

Hasilnya ada di `build\windows\x64\runner\Release\avd_launcher.exe`.

Jika Visual Studio sudah diperbaiki (beban kerja "Desktop development with C++") dan `flutter doctor` tidak lagi menandai masalah itu, `flutter build windows --release` adalah cara yang disarankan.

## Batasan

- Hanya mendukung Windows, karena path yang dicari adalah `emulator.exe` dan `adb.exe`.
- Perangkat fisik yang terlihat di adb ditampilkan, tetapi tidak dapat dihentikan dari aplikasi ini.
- Folder AVD yang tidak lengkap (ada direktori `.avd` tanpa file `.ini` yang sesuai) tidak muncul di `emulator -list-avds`, jadi juga tidak muncul di daftar aplikasi.
