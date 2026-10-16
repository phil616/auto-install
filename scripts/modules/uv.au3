#include "..\lib\Common.au3"

; Offline ZIP installation; PowerShell handles archive extraction and the user PATH.
Local $sHelper = _RequiredEnv("DEPLOY_ROOT") & "\scripts\Install-Uv.ps1"
Local $sCommand = _Quote(_NativeSystemDir() & "\WindowsPowerShell\v1.0\powershell.exe") & _
        ' -NoProfile -ExecutionPolicy Bypass -File ' & _Quote($sHelper) & _
        ' -Archive ' & _Quote(_RequiredEnv("DEPLOY_PACKAGE")) & _
        ' -Destination ' & _Quote(_RequiredEnv("DEPLOY_TARGET")) & _
        ' -LogDir ' & _Quote(_RequiredEnv("DEPLOY_LOG_DIR"))
Exit _Exec($sCommand)
