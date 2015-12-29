@echo off
setlocal enableextensions enabledelayedexpansion
path %SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0

:: Unattended install flag. When set, the script will not require user input.
set unattended=no
if "%1"=="/u" set unattended=yes

:: Make sure the script is running as admin
call :ensure_admin

:: Remove mpv from the %PATH%
powershell -Command ^
	$new_path = \"%~dp0/\".TrimEnd('\/'); ^
	$env_key_name = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; ^
	$env_key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($env_key_name, $true); ^
	$path_unexp = $env_key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); ^
	if (^^!$path_unexp) { Exit } ^
	if (^^!\";$path_unexp;\".Contains(\";$new_path;\")) { Exit } ^
	$path_unexp = \";$path_unexp;\".Replace(\";$new_path;\", ';').Trim(';'); ^
	$env_key.SetValue('Path', $path_unexp, [Microsoft.Win32.RegistryValueKind]::ExpandString)

:: Notify the shell of environment variable changes
call :notify_env_changed

:: Delete "App Paths" entry
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe" /f >nul

:: Delete HKCR subkeys
set classes_root_key=HKLM\SOFTWARE\Classes
reg delete "%classes_root_key%\Applications\mpv.exe" /f >nul
reg delete "%classes_root_key%\SystemFileAssociations\video\OpenWithList\mpv.exe" /f >nul
reg delete "%classes_root_key%\SystemFileAssociations\audio\OpenWithList\mpv.exe" /f >nul

:: Delete AutoPlay handlers
set autoplay_key=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers
reg delete "%autoplay_key%\Handlers\MpvPlayDVDMovieOnArrival" /f >nul
reg delete "%autoplay_key%\EventHandlers\PlayDVDMovieOnArrival" /v "MpvPlayDVDMovieOnArrival" /f >nul
reg delete "%autoplay_key%\Handlers\MpvPlayBluRayOnArrival" /f >nul
reg delete "%autoplay_key%\EventHandlers\PlayBluRayOnArrival" /v "MpvPlayBluRayOnArrival" /f >nul

:: Delete "Default Programs" entry
reg delete "HKLM\SOFTWARE\RegisteredApplications" /v "mpv" /f >nul
reg delete "HKLM\SOFTWARE\Clients\Media\mpv\Capabilities" /f >nul

:: Delete all OpenWithProgIds referencing ProgIds that start with io.mpv.
for /f "usebackq eol= delims=" %%k in (`reg query "%classes_root_key%" /f "io.mpv.*" /s /v /c`) do (
	set "key=%%k"
	echo !key!| findstr /r /i "^HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\\.[^\\][^\\]*\\OpenWithProgIds$" >nul
	if not errorlevel 1 (
		for /f "usebackq eol= tokens=1" %%v in (`reg query "!key!" /f "io.mpv.*" /v /c`) do (
			set "value=%%v"
			echo !value!| findstr /r /i "^io\.mpv\.[^\\][^\\]*$" >nul
			if not errorlevel 1 (
				echo Deleting !key!\!value!
				reg delete "!key!" /v "!value!" /f >nul
			)
		)
	)
)

:: Delete all ProgIds starting with io.mpv.
for /f "usebackq eol= delims=" %%k in (`reg query "%classes_root_key%" /f "io.mpv.*" /k /c`) do (
	set "key=%%k"
	echo !key!| findstr /r /i "^HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\io\.mpv\.[^\\][^\\]*$" >nul
	if not errorlevel 1 (
		echo Deleting !key!
		reg delete "!key!" /f >nul
	)
)

:: Notify the shell of file association changes
call :notify_assoc_changed

echo Uninstalled successfully
if [%unattended%] == [yes] exit 0
pause
exit 0

:die
	if not [%1] == [] echo %~1
	if [%unattended%] == [yes] exit 1
	pause
	exit 1

:ensure_admin
	:: 'openfiles' is just a commmand that is present on all supported Windows
	:: versions, requires admin privileges and has no side effects, see:
	:: https://stackoverflow.com/questions/4051883/batch-script-how-to-check-for-admin-rights
	openfiles >nul 2>&1
	if errorlevel 1 (
		echo This batch script requires administrator privileges. Right-click on
		echo mpv-uninstall.bat and select "Run as administrator".
		call :die
	)
	goto :EOF

:notify_env_changed
	powershell -Command ^
		Add-Type -TypeDefinition ' ^
			using System; ^
			using System.Runtime.InteropServices; ^
		^
			public static class NativeMethods { ^
				public static int HWND_BROADCAST = 0xffff; ^
				public static int WM_SETTINGCHANGE = 0x1a; ^
		^
				[DllImport(\"user32.dll\", SetLastError = true, CharSet = CharSet.Unicode)] ^
				public static extern bool SendNotifyMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam); ^
			}'; ^
		[NativeMethods]::SendNotifyMessage([NativeMethods]::HWND_BROADCAST, [NativeMethods]::WM_SETTINGCHANGE, [IntPtr]::Zero, 'Environment') ^| Out-Null

	goto :EOF

:notify_assoc_changed
	powershell -Command ^
		Add-Type -TypeDefinition ' ^
			using System; ^
			using System.Runtime.InteropServices; ^
		^
			public static class NativeMethods { ^
				public static int SHCNE_ASSOCCHANGED = 0x8000000; ^
				public static uint SHCNF_IDLIST = 0; ^
		^
				[DllImport(\"shell32.dll\")] ^
				public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2); ^
			}'; ^
		[NativeMethods]::SHChangeNotify([NativeMethods]::SHCNE_ASSOCCHANGED, [NativeMethods]::SHCNF_IDLIST, [IntPtr]::Zero, [IntPtr]::Zero)

	goto :EOF
