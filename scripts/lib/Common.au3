#include-once
#include <WinAPIProc.au3>

Opt("MustDeclareVars", 1)

Func _RequiredEnv($sName)
    Local $sValue = EnvGet($sName)
    If $sValue = "" Then
        ConsoleWrite("Missing environment variable: " & $sName & @CRLF)
        Exit 2
    EndIf
    Return $sValue
EndFunc

Func _Quote($sValue)
    If StringInStr($sValue, '"') Then Exit 2
    Return '"' & $sValue & '"'
EndFunc

Func _NativeSystemDir()
    ; A 32-bit interpreter must use Sysnative to launch native 64-bit system tools.
    If @OSArch = "X64" And Not @AutoItX64 Then Return @WindowsDir & "\Sysnative"
    Return @SystemDir
EndFunc

; Keep the process handle from CreateProcess: even very fast exits retain their exit code.
; Allocate the complete command line (the stock UDF uses a MAX_PATH-sized buffer).
Func _Start($sCommand)
    Local $tStartup = DllStructCreate($tagSTARTUPINFO)
    Local $tProcess = DllStructCreate($tagPROCESS_INFORMATION)
    Local $tCommand = DllStructCreate("wchar Text[" & StringLen($sCommand) + 1 & "]")
    DllStructSetData($tStartup, "Size", DllStructGetSize($tStartup))
    DllStructSetData($tCommand, "Text", $sCommand)
    Local $aResult = DllCall("kernel32.dll", "bool", "CreateProcessW", "ptr", 0, "struct*", $tCommand, _
            "ptr", 0, "ptr", 0, "bool", False, "dword", 0x08000000, "ptr", 0, _
            "wstr", _RequiredEnv("DEPLOY_ROOT"), "struct*", $tStartup, "struct*", $tProcess)
    If @error Then Return SetError(1, 0, 0)
    If Not $aResult[0] Then Return SetError(1, 0, 0)
    _WinAPI_CloseHandle(DllStructGetData($tProcess, "hThread"))
    ConsoleWrite("Started PID=" & DllStructGetData($tProcess, "ProcessID") & @CRLF)
    Return DllStructGetData($tProcess, "hProcess")
EndFunc

Func _Wait($hProcess, $iSeconds)
    Local $iWait = _WinAPI_WaitForSingleObject($hProcess, $iSeconds * 1000)
    If @error Or $iWait <> 0 Then
        _WinAPI_CloseHandle($hProcess)
        ConsoleWrite("TIMEOUT/WAIT ERROR: installer may still be running. Stop and inspect before retrying." & @CRLF)
        Return 124
    EndIf
    Local $iCode = _WinAPI_GetExitCodeProcess($hProcess)
    Local $iError = @error
    _WinAPI_CloseHandle($hProcess)
    If $iError Then Return 1
    ConsoleWrite("Process exit=" & $iCode & @CRLF)
    Return $iCode
EndFunc

Func _Exec($sCommand)
    Local $hProcess = _Start($sCommand)
    If @error Then Return 1
    Return _Wait($hProcess, Number(_RequiredEnv("DEPLOY_TIMEOUT")))
EndFunc
