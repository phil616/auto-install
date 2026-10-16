#include "..\lib\Common.au3"

; Suppress automatic reboot; preserve the native MSI exit code (including 3010).
Local $sCommand = _Quote(_NativeSystemDir() & "\msiexec.exe") & " /i " & _Quote(_RequiredEnv("DEPLOY_PACKAGE")) & _
        ' /qn /norestart REBOOT=ReallySuppress /L*v ' & _Quote(_RequiredEnv("DEPLOY_LOG_DIR") & "\msi.log")
$sCommand &= " " & EnvGet("DEPLOY_ARGUMENTS")
Exit _Exec($sCommand)
