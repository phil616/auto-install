#include "..\lib\Common.au3"

; Arguments belong to the specific vendor and are configured in the plugin manifest.
Exit _Exec(_Quote(_RequiredEnv("DEPLOY_PACKAGE")) & " " & EnvGet("DEPLOY_ARGUMENTS"))
