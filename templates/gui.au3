#include "..\lib\Common.au3"

; Copy to scripts/modules/<id>.au3, then replace this fail-closed placeholder.
; Use tools/autoit/install/Au3Info_x64.exe to inspect actual window/control IDs.
ConsoleWrite("GUI template is not configured; refusing to launch an installer." & @CRLF)
Exit 2

; Example pattern only (uncomment and adapt after recording the real installer):
; Local $hProcess = _Start(_Quote(_RequiredEnv("DEPLOY_PACKAGE")))
; If @error Then Exit 1
; Local $hWindow = WinWait("[TITLE:Exact installer title; CLASS:#32770]", "Expected page text", 30)
; If Not $hWindow Then Exit 124
; Check window identity and each page before interacting; use finite waits.
; If Not ControlClick($hWindow, "", "[ID:1234]") Then Exit 1
; Exit _Wait($hProcess, Number(_RequiredEnv("DEPLOY_TIMEOUT")))
