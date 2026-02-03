Scriptname IntelEngine_PlayerAlias extends ReferenceAlias
{
    IntelEngine Player Alias Script v1.0

    This script is attached to the PlayerAlias on the IntelEngine quest.
    It handles:
    - Starting the quest on first install (no SEQ file needed!)
    - Calling Maintenance on every game load

    Modern Approach:
    - Quest is NOT marked "Start Game Enabled"
    - PlayerAlias fills automatically (Specific Reference = Player)
    - OnInit fires on first install → starts quest, initializes mod
    - OnPlayerLoadGame fires on every load → re-registers decorators, recovers tasks

    This eliminates the need for SEQ files entirely.
}

; =============================================================================
; PROPERTIES
; =============================================================================

IntelEngine_Core Property Core Auto
{Reference to the core script for initialization}

; =============================================================================
; EVENTS
; =============================================================================

Event OnInit()
    ; This fires when the mod is first installed
    ; The player alias auto-fills because it's set to Specific Reference → Player
    Debug.Trace("IntelEngine: PlayerAlias OnInit - First install detected")

    ; Start the quest if it's not running
    Quest parentQuest = GetOwningQuest()
    If parentQuest && !parentQuest.IsRunning()
        Debug.Trace("IntelEngine: Starting quest via PlayerAlias")
        parentQuest.Start()
    EndIf

    ; Small delay to ensure quest is fully started
    Utility.Wait(0.5)

    ; Call maintenance for first-time setup
    If Core
        Core.Maintenance(true)  ; true = first install
    EndIf
EndEvent

Event OnPlayerLoadGame()
    ; This fires every time a save is loaded (after the first install)
    ; OnPlayerLoadGame ONLY fires on ReferenceAlias scripts pointing to the player
    Debug.Trace("IntelEngine: PlayerAlias OnPlayerLoadGame - Save loaded")

    ; Ensure quest is running
    Quest parentQuest = GetOwningQuest()
    If parentQuest && !parentQuest.IsRunning()
        Debug.Trace("IntelEngine: Quest not running, starting it")
        parentQuest.Start()
        Utility.Wait(0.5)
    EndIf

    ; Call maintenance for save load
    If Core
        Core.Maintenance(false)  ; false = subsequent load
    EndIf
EndEvent
