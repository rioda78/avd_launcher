# AVD Launcher

Aplikasi desktop Windows untuk memilih Android Virtual Device (AVD) dan menjalankannya.

## Menjalankan

Hasil build yang sudah diverifikasi:

`build\windows\x64\runner\Release\avd_launcher.exe`

1. Pastikan Android SDK sudah terpasang. Aplikasi mencari `emulator.exe` dan `adb.exe` dari, berurutan:
   - folder yang Anda pilih secara manual (disimpan di `%APPDATA%\AVD Launcher\settings.json`)
   - `ANDROID_HOME`
   - `ANDROID_SDK_ROOT`
   - `%LOCALAPPDATA%\Android\Sdk`
2. Jalankan `avd_launcher.exe` di atas, atau dari folder proyek:

   ```bat
   flutter run -d windows --release
   ```

   `flutter run` memerlukan instalasi Visual Studio yang lengkap (lihat bagian Membangun).

Emulator dijalankan terpisah dari aplikasi. Menutup AVD Launcher tidak menghentikan emulator yang sudah mulai.

Saat Mulai, aplikasi meneruskan `ANDROID_SDK_ROOT`, `ANDROID_HOME`, dan `ANDROID_AVD_HOME`, menulis log emulator ke folder pengaturan, dan memantau `adb devices` sampai perangkat tampil atau prosesnya berhenti. Jika system image AVD tidak ada, pesan kesalahan ditampilkan tanpa menunggu.

Pengaturan (misalnya folder SDK manual) disimpan ke `settings.json` pada lokasi pertama yang dapat ditulisi, berurutan:

- direktori dukungan aplikasi (`path_provider`)
- `%LOCALAPPDATA%\AVD Launcher`
- folder yang sama dengan `avd_launcher.exe` (portabel)

Jika sebuah berkas sudah ada di salah satu lokasi itu, atau di lokasi lama `%APPDATA%\AVD Launcher`, aplikasi membacanya dari sana. Jalur berkas yang dipakai ditampilkan di jendela aplikasi.

## Fitur

- Daftar AVD dengan tombol Segarkan
- Mulai AVD yang dipilih
- Opsi boot dingin (`-no-snapshot-load`), hapus data (`-wipe-data`, dengan konfirmasi), dan tanpa audio (`-no-audio`)
- Daftar perangkat `adb devices -l`, dan Hentikan untuk emulator (`adb -s emulator-XXXX emu kill`)
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
- Aplikasi tidak membuat, mengubah, atau menghapus AVD. Itu tetap dilakukan di Android Studio atau `avdmanager`.
- Perangkat fisik yang terlihat di adb ditampilkan, tetapi tidak dapat dihentikan dari aplikasi ini.
- Folder AVD yang tidak lengkap (ada direktori `.avd` tanpa file `.ini` yang sesuai) tidak muncul di `emulator -list-avds`, jadi juga tidak muncul di daftar aplikasi.
