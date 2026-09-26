@echo off
REM Menjalankan MasPart Mobile di emulator dengan ukuran jendela yang muat layar laptop.
REM   jalankan-emulator.bat        -> backend LOKAL (http://10.0.2.2:8001, backend harus jalan)
REM   jalankan-emulator.bat prod   -> backend PRODUKSI (https://maspart.tech)

setlocal
set AVD=MasPart_API36
set SCALE=0.300000
set SDK=%LOCALAPPDATA%\Android\Sdk
set ADB=%SDK%\platform-tools\adb.exe
set INI=%USERPROFILE%\.android\avd\%AVD%.avd\emulator-user.ini

set API=http://10.0.2.2:8001
if /i "%~1"=="prod" set API=https://maspart.tech

"%ADB%" devices | findstr /b "emulator-5554" >nul
if not errorlevel 1 goto booted

REM Emulator mati: paksa ukuran jendela (file ini ditulis ulang emulator saat ditutup).
powershell -NoProfile -Command "$f='%INI%'; if (Test-Path $f) { (Get-Content $f) -replace '^window\.scale = .*','window.scale = %SCALE%' -replace '^window\.y = .*','window.y = 0' | Set-Content -Encoding ascii $f }"

echo Menyalakan emulator %AVD% ...
REM -gpu swiftshader_indirect: render lewat software. Mode GPU "host" membuat layar app membeku/hitam di laptop ini.
REM Wajib dipasangkan dengan --no-enable-impeller di bawah (lihat catatannya).
start "" "%SDK%\emulator\emulator.exe" -avd %AVD% -gpu swiftshader_indirect
"%ADB%" wait-for-device

:waitboot
for /f %%a in ('"%ADB%" -s emulator-5554 shell getprop sys.boot_completed 2^>nul') do if "%%a"=="1" goto booted
timeout /t 2 /nobreak >nul
goto waitboot

:booted
echo Emulator siap. Menjalankan aplikasi (API_BASE_URL=%API%) ...
cd /d "%~dp0"
REM --no-enable-impeller: renderer Impeller memakai fence (glWaitSync) yang membuat
REM penerjemah GLES SwiftShader error 0x501 lalu emulator CRASH (APPCRASH qemu). Skia aman.
call C:\src\flutter\bin\flutter.bat run -d emulator-5554 --no-enable-impeller --dart-define=API_BASE_URL=%API%
endlocal
