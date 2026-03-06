#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; V Rising Macro Manager (Bloodcraft UI)
; Created by Navist • AI-assisted
; ============================================================

; =========================
; Globals / Settings
; =========================
global chatKey := "Enter"
global sendDelay := 50
global themeName := "Bloodcraft"   ; "Bloodcraft" or "Light"

global gTitleLogoPath := A_ScriptDir "\assets\bloodcraft_resized.ico"
global gHelpLogoPath := A_ScriptDir "\assets\bloodcraft_resized.png"  ; prefer PNG for panel logo (optional)

global picThemeIcon
global themeIconBlood := A_ScriptDir "\icons\blood_droplet.png"
global themeIconRest := A_ScriptDir "\icons\lantern.png"

global iniPath := A_ScriptDir "\vrising_macros.ini"

; =========================
; Profiles
; =========================
global profilesDir := A_ScriptDir "\profiles"
global appIniPath := A_ScriptDir "\app_settings.ini"
global currentProfile := "Default"
global ddlProfile
global profileList := []
global gProfileUiUpdating := false

; Runtime toggles
global gSuspended := false
global gGameFocusOnly := true
global gGameExe := "VRising.exe"
global lvIndexMap := []  ; ListView row -> bindings index mapping (for search/filter)

if FileExist(gTitleLogoPath)
    TraySetIcon(gTitleLogoPath)

; Theming buckets
global themedText := []      ; text labels
global themedInputs := []    ; edit boxes
global themedOther := []     ; checkbox, ddl, buttons
global btnTheme  ; theme toggle button (needs text update on theme change)

global gameButtons := []          ; holds the Text-controls that act like buttons
global hoveredBtn := 0            ; currently hovered control (GuiCtrl)
global tooltipMap := Map()        ; ctrlHwnd -> tooltip text
global tooltipHoverHwnd := 0      ; ctrl currently hovered for tooltip
global tooltipArmed := false      ; waiting to show tooltip
global tooltipDelayMs := 650      ; hover delay before tooltip appears

; Custom titlebar globals
global hdrBar, hdrTitle, btnMin, btnClose, hdrSep
global titleBarH := 34
global y0 := titleBarH + 8
global y0Offset := 355  ; vertical offset for the bottom buttons (Save, Load, Rebind, Add, Update, Delete)

; UI globals
global mainGui, lv
global edtHotkey, ddlAction, chkEnabled, edtCommands
global edtChatKey, edtDelay
global txtFooter
global picLogo
global supportPopupHwnd := 0
global supportHookInstalled := false
global txtStatus
global statusTimerRunning := false
global APP_NAME := "V Rising Macro Manager"
global APP_VERSION := "v2.5.0"
A_IconTip := APP_NAME " " APP_VERSION

; Binding system
global bindings := []              ; Array of binding objects
global hotkeyRegistry := Map()     ; hotkey string -> callback func

; =========================
; Core chat send functions
; =========================
SendChat(msg) {
    global chatKey, sendDelay
    if (msg = "")
        return
    Send "{" chatKey "}"
    Sleep sendDelay
    Send msg
    Sleep sendDelay
    Send "{Enter}"
}

PrefillChat(msg) {
    global chatKey, sendDelay
    if (msg = "")
        return
    Send "{" chatKey "}"
    Sleep sendDelay
    Send msg
}

; =========================
; Binding system (dynamic)
; =========================
MakeCallback(bindingIndex) {
    return (*) => RunBinding(bindingIndex)
}

RunBinding(i) {
    global bindings, sendDelay
    global gSuspended, gGameFocusOnly, gGameExe
    if (gSuspended)
        return
    if (gGameFocusOnly && !WinActive("ahk_exe " gGameExe))
        return
    if (i < 1 || i > bindings.Length)
        return

    b := bindings[i]
    if !b.HasProp("enabled") || !b.enabled
        return

    cmds := b.commands

    switch b.action {
        ; SendChat handles multi-line sequences (one chat per line)
        case "SendChat":
            for _, line in cmds {
                if (Trim(line) != "")
                    SendChat(line)
                Sleep sendDelay
            }

            ; PrefillChat opens chat and types without sending
        case "PrefillChat":
            PrefillChat(cmds.Length >= 1 ? cmds[1] : "")

        default:
            return
    }
}

UnregisterAllHotkeys() {
    global hotkeyRegistry
    for hk, cb in hotkeyRegistry {
        try Hotkey hk, cb, "Off"
    }
    hotkeyRegistry.Clear()
}

; =========================
; Duplicate hotkey detection
; =========================
NormalizeHotkey(hk) {
    return StrLower(Trim(hk))
}

PreviewBinding(b) {
    try {
        if (b.commands.Length >= 1) {
            p := b.commands[1]
            if (b.commands.Length > 1)
                p .= " (+" (b.commands.Length - 1) " more)"
            return p
        }
    }
    return ""
}

FindDuplicateHotkey(hk, skipIndex := 0) {
    ; Returns the FIRST conflicting index, or 0 if none.
    global bindings
    norm := NormalizeHotkey(hk)
    if (norm = "")
        return 0

    loop bindings.Length {
        i := A_Index
        if (i = skipIndex)
            continue
        b := bindings[i]
        if (NormalizeHotkey(b.hotkey) = norm)
            return i
    }
    return 0
}

RegisterAllHotkeys() {
    global bindings, hotkeyRegistry
    UnregisterAllHotkeys()

    seen := Map()          ; normalizedHotkey -> firstIndex
    dupReport := ""        ; text blob for MsgBox

    loop bindings.Length {
        b := bindings[A_Index]
        hk := Trim(b.hotkey)

        if (hk = "" || !b.enabled)
            continue

        n := NormalizeHotkey(hk)

        if (seen.Has(n)) {
            first := seen[n]
            dupReport .= "Hotkey '" hk "' is used by rows " first " and " A_Index " (row " A_Index " skipped)`n"
            continue
        }

        seen[n] := A_Index

        cb := MakeCallback(A_Index)
        hotkeyRegistry[hk] := cb
        try Hotkey hk, cb, "On"
    }

    if (dupReport != "") {
        MsgBox(
            "Some enabled bindings share the same hotkey. Only the FIRST one was registered:`n`n" dupReport,
            "Duplicate Hotkeys",
            "Icon!"
        )
    }
}

; =========================
; INI save/load
; NOTE: multi-line INI values can be finicky on some systems.
; If it ever drops lines again, we can switch to cmd1/cmd2 storage.
; =========================

; =========================
; Profile system
; =========================

EnsureProfilesDir() {
    global profilesDir
    if !DirExist(profilesDir) {
        try DirCreate(profilesDir)
    }
}

SanitizeProfileName(name) {
    n := Trim(name)
    ; Remove characters that are invalid in Windows filenames
    n := RegExReplace(n, '[\\\/\:\*\?\"<>\|]', "")
    n := RegExReplace(n, '\s+', " ")
    n := Trim(n)
    if (n = "")
        n := "Default"
    return n
}

GetProfileIniPath(name) {
    global profilesDir
    safe := SanitizeProfileName(name)
    return profilesDir "\\" safe ".ini"
}

ListProfiles() {
    global profilesDir
    list := []
    EnsureProfilesDir()

    loop files profilesDir "\\*.ini" {
        fn := A_LoopFileName
        name := RegExReplace(fn, "\.ini$", "")
        if (name != "")
            list.Push(name)
    }

    if (list.Length = 0)
        list.Push("Default")

    ArraySort(list)

    ; Move Default to top if present
    for i, v in list {
        if (v = "Default") {
            list.RemoveAt(i)
            list.InsertAt(1, "Default")
            break
        }
    }

    return list
}

ArraySort(arr) {
    loop arr.Length {
        loop arr.Length - A_Index {
            if (StrCompare(arr[A_Index], arr[A_Index + 1]) > 0) {
                temp := arr[A_Index]
                arr[A_Index] := arr[A_Index + 1]
                arr[A_Index + 1] := temp
            }
        }
    }

    for i, v in arr {
        if (v = "Default") {
            arr.RemoveAt(i)
            arr.InsertAt(1, "Default")
            break
        }
    }

    return arr
}

LoadAppLastProfile() {
    global appIniPath, currentProfile
    try {
        currentProfile := IniRead(appIniPath, "App", "lastProfile", currentProfile)
    }
    catch {
        ; ignore
    }
    currentProfile := SanitizeProfileName(currentProfile)
}

SaveAppLastProfile() {
    global appIniPath, currentProfile
    try IniWrite currentProfile, appIniPath, "App", "lastProfile"
}

InitProfiles() {
    global iniPath, profilesDir, currentProfile

    EnsureProfilesDir()

    ; Migration: if the old single-file INI exists and Default profile doesn't, copy it in.
    oldIni := iniPath
    defaultIni := GetProfileIniPath("Default")

    if FileExist(oldIni) && !FileExist(defaultIni) {
        try FileCopy oldIni, defaultIni, 1
    }

    LoadAppLastProfile()

    ; If selected profile INI doesn't exist yet, fall back to Default
    if !FileExist(GetProfileIniPath(currentProfile)) {
        currentProfile := "Default"
    }

    SaveAppLastProfile()
}

RefreshProfileDropdown(keepSelection := true) {
    global ddlProfile, profileList, currentProfile, gProfileUiUpdating

    profileList := ListProfiles()

    if !IsSet(ddlProfile) || !ddlProfile
        return

    gProfileUiUpdating := true

    ddlProfile.Delete()
    for _, name in profileList
        ddlProfile.Add([name])

    if keepSelection {
        ; Select currentProfile if present
        idx := 0
        loop profileList.Length {
            if (profileList[A_Index] = currentProfile) {
                idx := A_Index
                break
            }
        }
        ddlProfile.Choose(idx ? idx : 1)
    } else {
        ddlProfile.Choose(1)
    }

    gProfileUiUpdating := false
}

OnProfileDropdownChanged() {
    global ddlProfile, gProfileUiUpdating
    if (gProfileUiUpdating)
        return
    name := ddlProfile.Text
    if (name != "")
        SwitchProfile(name)
}

SaveCurrentProfile() {
    global currentProfile
    SaveToIni(GetProfileIniPath(currentProfile))
    SaveAppLastProfile()
}

LoadCurrentProfile() {
    global currentProfile
    ok := LoadFromIni(GetProfileIniPath(currentProfile))
    if (!ok)
        return false
    SaveAppLastProfile()
    return true
}

SwitchProfile(newName) {
    global currentProfile
    newName := SanitizeProfileName(newName)
    if (newName = currentProfile)
        return

    ; Always save current before switching (prevents accidental loss)
    SaveCurrentProfile()

    currentProfile := newName

    ; If profile doesn't exist, seed an empty file from current state
    if !FileExist(GetProfileIniPath(currentProfile)) {
        SaveCurrentProfile()
    } else {
        LoadCurrentProfile()
    }

    ; Refresh UI + hotkeys
    RefreshListView()
    ApplySettings()
    RegisterAllHotkeys()
    SaveAppLastProfile()
}

ShowProfileMenu(*) {
    global currentProfile

    m := Menu()

    m.Add("New Profile…", (*) => CreateNewProfile())
    m.Add("Rename Profile…", (*) => RenameCurrentProfile())
    m.Add()
    m.Add("Duplicate Profile…", (*) => DuplicateCurrentProfile())
    m.Add()
    m.Add("Delete Profile", (*) => DeleteCurrentProfile())

    if (currentProfile = "Default")
        m.Disable("Delete Profile")

    m.Show()
}

CreateNewProfile() {
    global currentProfile
    res := InputBox("Enter a new profile name:", "New Profile", "w320")
    if (res.Result != "OK")
        return
    name := res.Value
    name := SanitizeProfileName(name)
    if (name = "")
        return

    ; Save current to preserve it, then create new profile from current state
    SaveCurrentProfile()
    currentProfile := name
    SaveCurrentProfile()

    RefreshProfileDropdown(true)
    RefreshListView()
    RegisterAllHotkeys()
}

RenameCurrentProfile() {
    global currentProfile

    if (currentProfile = "Default") {
        MsgBox("The Default profile can't be renamed.", "Rename Profile", "Icon!")
        return
    }

    res := InputBox("Rename profile '" currentProfile "' to:", "Rename Profile", "w360")
    if (res.Result != "OK")
        return
    newName := res.Value
    newName := SanitizeProfileName(newName)

    if (newName = "" || newName = currentProfile)
        return

    oldPath := GetProfileIniPath(currentProfile)
    newPath := GetProfileIniPath(newName)

    if FileExist(newPath) {
        MsgBox("A profile named '" newName "' already exists.", "Rename Profile", "Icon!")
        return
    }

    try FileMove oldPath, newPath, 1
    currentProfile := newName
    SaveAppLastProfile()

    RefreshProfileDropdown(true)
}

DuplicateCurrentProfile() {
    global currentProfile
    res := InputBox("Duplicate profile '" currentProfile "' as:", "Duplicate Profile", "w360")
    if (res.Result != "OK")
        return
    copyName := res.Value
    copyName := SanitizeProfileName(copyName)
    if (copyName = "" || copyName = currentProfile)
        return

    src := GetProfileIniPath(currentProfile)
    dst := GetProfileIniPath(copyName)

    if FileExist(dst) {
        MsgBox("A profile named '" copyName "' already exists.", "Duplicate Profile", "Icon!")
        return
    }

    try FileCopy src, dst, 1
    currentProfile := copyName
    SaveAppLastProfile()

    RefreshProfileDropdown(true)
}

DeleteCurrentProfile() {
    global currentProfile
    if (currentProfile = "Default")
        return

    r := MsgBox("Delete profile '" currentProfile "'?`n`nThis removes the profile INI file from:`n" GetProfileIniPath(
        currentProfile), "Delete Profile", "YesNo Icon!")
    if (r != "Yes")
        return

    try FileDelete GetProfileIniPath(currentProfile)

    currentProfile := "Default"
    LoadCurrentProfile()
    SaveAppLastProfile()

    RefreshProfileDropdown(true)
    RefreshListView()
    RegisterAllHotkeys()
}

SaveToIni(path := "") {
    global iniPath, bindings, chatKey, sendDelay, themeName, gGameFocusOnly, gGameExe

    if (path = "")
        path := iniPath

    try FileDelete path

    IniWrite chatKey, path, "Settings", "chatKey"
    IniWrite sendDelay, path, "Settings", "sendDelay"
    IniWrite themeName, path, "Settings", "theme"
    IniWrite gGameFocusOnly ? 1 : 0, path, "Settings", "gameFocusOnly"
    IniWrite gGameExe, path, "Settings", "gameExe"
    IniWrite bindings.Length, path, "Meta", "count"

    loop bindings.Length {
        b := bindings[A_Index]
        section := "Bind" A_Index

        IniWrite b.enabled ? 1 : 0, path, section, "enabled"
        IniWrite b.hotkey, path, section, "hotkey"
        IniWrite b.action, path, section, "action"

        ; Store commands safely as cmdCount + cmd1..cmdN
        IniWrite b.commands.Length, path, section, "cmdCount"
        loop b.commands.Length {
            IniWrite b.commands[A_Index], path, section, "cmd" A_Index
        }
    }
}

LoadFromIni(path := "") {
    global iniPath, bindings, chatKey, sendDelay, themeName, gGameFocusOnly, gGameExe

    if (path = "")
        path := iniPath

    if !FileExist(path)
        return false

    chatKey := IniRead(path, "Settings", "chatKey", chatKey)
    sendDelay := IniRead(path, "Settings", "sendDelay", sendDelay)
    themeName := IniRead(path, "Settings", "theme", themeName)
    gGameFocusOnly := (IniRead(path, "Settings", "gameFocusOnly", gGameFocusOnly ? 1 : 0) + 0) = 1
    gGameExe := IniRead(path, "Settings", "gameExe", gGameExe)

    count := (IniRead(path, "Meta", "count", 0) + 0)
    bindings := []

    loop count {
        section := "Bind" A_Index

        enabled := (IniRead(path, section, "enabled", 1) + 0)
        hk := IniRead(path, section, "hotkey", "")
        action := IniRead(path, section, "action", "SendChat")

        ; Preferred: cmdCount/cmd#
        cmdCount := (IniRead(path, section, "cmdCount", 0) + 0)
        cmds := []

        if (cmdCount > 0) {
            loop cmdCount {
                c := IniRead(path, section, "cmd" A_Index, "")
                if (Trim(c) != "")
                    cmds.Push(c)
            }
        } else {
            ; Fallback: legacy multiline "commands" key (best-effort)
            block := IniRead(path, section, "commands", "")
            cmds := ParseCommands(block)
        }

        bindings.Push({
            enabled: enabled = 1,
            hotkey: hk,
            action: action,
            commands: cmds
        })
    }

    return true
}

ParseCommands(text) {
    lines := []
    for line in StrSplit(text, "`n", "`r") {
        l := Trim(line)
        if (l != "")
            lines.Push(l)
    }
    return lines
}

CommandsToBlock(cmds) {
    block := ""
    for _, c in cmds
        block .= c "`n"
    return RTrim(block, "`n")
}

; =========================
; Theme
; =========================

GetThemePalette(name) {
    if (name = "Bloodcraft") {
        return Map(
            "bg", "0B0B10",        ; window background
            "panel", "161622",     ; panel containers
            "text", "E8E8E8",
            "muted", "9A9AA3",
            "divider", "3A3A45",    ; separator lines (visible on dark)
            "accent", "C1121F",    ; blood red
            "accent2", "2A0A0E",   ; deep blood
            "editBg", "101018",    ; inputs slightly darker
            "editText", "E8E8E8",
            "lvBg", "11111B",      ; list slightly different
            "lvText", "E8E8E8",
            "font", "Segoe UI",
            "btnHighlightText", "FFFFFF",
        )
    } else {
        return Map(
            "bg", "F2F2F2",
            "panel", "FFFFFF",
            "text", "111111",
            "muted", "333333",
            "divider", "C9C9C9",
            "accent", "8B0000",
            "accent2", "5A0000",
            "editBg", "FFFFFF",
            "editText", "111111",
            "lvBg", "FFFFFF",
            "lvText", "111111",
            "font", "Segoe UI",
            "btnHighlightText", "FFFFFF",
        )
    }
}

ApplyTheme() {
    global mainGui, lv, themeName
    global themedText, themedInputs, themedOther, txtFooter
    global hdrBar, hdrTitle, btnMin, btnClose, hdrSep, btnTheme

    global uiSepTop, uiSepMid, uiSepBottom, uiSepHelp

    pal := GetThemePalette(themeName)

    mainGui.BackColor := pal["bg"]
    mainGui.SetFont("s10 c" pal["text"], pal["font"])

    ; Divider color: ensure separators are visible (especially in Bloodcraft / dark)
    divCol := pal.Has("divider") ? pal["divider"] : pal["muted"]

    if IsSet(uiSepTop)
        try uiSepTop.Opt("Background" divCol)
    if IsSet(uiSepMid)
        try uiSepMid.Opt("Background" divCol)
    if IsSet(uiSepHelp)
        try uiSepHelp.Opt("Background" divCol)
    if IsSet(uiSepBottom)
        try uiSepBottom.Opt("Background" divCol)

    ; Custom title bar
    try hdrBar.Opt("Background" pal["panel"])
    try hdrTitle.SetFont("c" pal["text"])
    if IsSet(hdrSep)
        try hdrSep.Opt("Background" pal["accent"])

    ; Window buttons
    try btnMin.Opt("Background" pal["panel"])
    try btnMin.SetFont("c" pal["text"])
    try btnClose.Opt("Background" pal["accent"])
    try btnClose.SetFont("cFFFFFF")

    ; Labels
    for _, ctrl in themedText {
        try ctrl.SetFont("c" pal["text"])
    }

    ; Inputs
    for _, ctrl in themedInputs {
        try ctrl.Opt("Background" pal["editBg"])
        try ctrl.SetFont("c" pal["editText"])
    }

    ; Other controls
    for _, ctrl in themedOther {
        try ctrl.Opt("Background" pal["panel"])
        try ctrl.SetFont("c" pal["text"])
    }

    ; ListView
    try lv.Opt("Background" pal["lvBg"])
    try lv.SetFont("c" pal["lvText"])

    if IsSet(txtFooter) {
        if (themeName = "Bloodcraft") {
            try txtFooter.SetFont("c" pal["accent"])
        } else {
            try txtFooter.SetFont("c" pal["muted"])
        }
    }

    if IsSet(txtStatus) {
        if (themeName = "Bloodcraft") {
            try txtStatus.SetFont("c" pal["muted"])
        }
        else {
            try txtStatus.SetFont("c" pal["muted"])
        }

    }

    if IsSet(btnTheme) {
        if (themeName = "Bloodcraft") {
            try btnTheme.Opt("Background" pal["accent2"])
            try btnTheme.SetFont("c" pal["text"])
        } else {
            try btnTheme.Opt("Background" pal["panel"])
            try btnTheme.SetFont("c" pal["text"])
        }
    }

    ; Ensure stateful controls keep their special styling after theme application
    try UpdateSuspendButtonText()

}

; =========================
; =========================
; Action helper text
; =========================
UpdateActionHelpText() {
    global ddlAction, txtActionHelp
    if !IsSet(ddlAction) || !IsSet(txtActionHelp)
        return

    act := ddlAction.Text
    switch act {
        case "SendChat":
            txtActionHelp.Text :=
            "SendChat`n`n• Sends ALL command lines`n• One chat message per line`n• Uses your Chat Key + delay settings"
        case "PrefillChat":
            txtActionHelp.Text :=
            "PrefillChat`n`n• Opens chat and types ONLY the first line`n• Does NOT press Enter`n• Lets you edit before sending"
        default:
            txtActionHelp.Text := ""
    }
}

; GUI helpers
; =========================
DragWindow(hwnd) {
    PostMessage 0xA1, 2, , , "ahk_id " hwnd  ; WM_NCLBUTTONDOWN, HTCAPTION
}

ToggleTheme() {
    global themeName
    themeName := (themeName = "Bloodcraft") ? "Light" : "Bloodcraft"
    ApplyTheme()
    UpdateThemeButtonText()
    SaveToIni()
    ClearHoveredButton()
}

global _settingsApplyTimerArmed := false

ScheduleSettingsApply() {
    global _settingsApplyTimerArmed
    _settingsApplyTimerArmed := true
    SetTimer ApplySettingsDebounced, -700
}

ApplySettingsDebounced() {
    global _settingsApplyTimerArmed
    if (!_settingsApplyTimerArmed)
        return
    _settingsApplyTimerArmed := false
    ApplySettings(true)
    SetStatus("Settings applied")
}

ApplySettings(rebind := true) {
    global edtChatKey, edtDelay, chatKey, sendDelay
    chatKey := Trim(edtChatKey.Text)
    d := Trim(edtDelay.Text)
    if (d != "" && d ~= "^\d+$")
        sendDelay := d + 0
    if rebind
        RegisterAllHotkeys()
}

FocusSearch() {
    global edtSearch
    if !IsSet(edtSearch)
        return
    try {
        edtSearch.Focus()
        edtSearch.SelectAll()
    }
}

ToggleSuspend() {
    global gSuspended
    gSuspended := !gSuspended

    ; update UI + tray
    UpdateSuspendButtonText()
    try {
        if (gSuspended)
            A_TrayMenu.Check("Suspend Macros")
        else
            A_TrayMenu.Uncheck("Suspend Macros")
    }

    SetStatus(gSuspended ? "Macros suspended" : "Macros enabled")
}

UpdateSuspendButtonText() {
    global btnSuspend, gSuspended
    if !IsSet(btnSuspend)
        return

    if (gSuspended) {
        btnSuspend.Text := "Macros: OFF"
        ; Crimson (OFF)
        try btnSuspend.Opt("BackgroundE74C3C")
        try btnSuspend.SetFont("cFFFFFF")
    } else {
        btnSuspend.Text := "Macros: ON"
        ; Emerald (ON)
        try btnSuspend.Opt("Background2ECC71")
        try btnSuspend.SetFont("c000000")
    }
}

SyncUiFromSettings() {
    global chkGameOnly, gGameFocusOnly
    if IsSet(chkGameOnly)
        chkGameOnly.Value := gGameFocusOnly ? 1 : 0
    UpdateSuspendButtonText()
}

MoveSelected(dir) {
    global bindings
    idx := GetSelectedBindingIndex()
    if (!idx)
        return

    newIdx := idx + dir
    if (newIdx < 1 || newIdx > bindings.Length)
        return

    ; swap
    tmp := bindings[idx]
    bindings[idx] := bindings[newIdx]
    bindings[newIdx] := tmp

    RefreshListView()
    SelectBindingInList(newIdx)
    RegisterAllHotkeys()
    SetStatus(dir < 0 ? "Moved up" : "Moved down")
}

CreateGameButton(gui, x, y, w, h, text, callback, statusMsg := "") {
    global themedOther, gameButtons

    btn := gui.AddText("x" x " y" y " w" w " h" h " Center Border 0x200", text)

    btn.OnEvent("Click", (*) => (
        FlashCtrl(btn),
        callback.Call(),
        (statusMsg != "" ? SetStatus(statusMsg) : 0)
    ))

    themedOther.Push(btn)
    if IsSet(gameButtons)
        gameButtons.Push(btn)

    return btn
}

; =========================
; Tooltip helpers (hover-tooltips)
; =========================
AddTooltip(ctrl, text) {
    global tooltipMap
    try tooltipMap[ctrl.Hwnd] := text
}

HideTooltip() {
    global tooltipHoverHwnd, tooltipArmed
    tooltipHoverHwnd := 0
    tooltipArmed := false
    ToolTip()
}

ArmTooltip(gui, ctrlHwnd) {
    global tooltipMap, tooltipHoverHwnd, tooltipArmed, tooltipDelayMs
    if (!tooltipMap.Has(ctrlHwnd)) {
        HideTooltip()
        return
    }
    if (tooltipHoverHwnd = ctrlHwnd && tooltipArmed)
        return
    tooltipHoverHwnd := ctrlHwnd
    tooltipArmed := true
    SetTimer ShowTooltip.Bind(gui), -tooltipDelayMs
}

ShowTooltip(gui) {
    global tooltipMap, tooltipHoverHwnd, tooltipArmed
    if (!tooltipArmed || tooltipHoverHwnd = 0)
        return
    if (WinActive("ahk_id " gui.Hwnd) = 0)
        return
    MouseGetPos , , &winHwnd, &ctrlHwnd, 2
    if (winHwnd != gui.Hwnd || ctrlHwnd != tooltipHoverHwnd) {
        HideTooltip()
        return
    }
    try ToolTip(tooltipMap[ctrlHwnd])
}

EnableButtonHover(gui) {
    ; WM_MOUSEMOVE = 0x200
    OnMessage(0x200, WM_MOUSEMOVE_Hover.Bind(gui))
}

WM_MOUSEMOVE_Hover(gui, wParam, lParam, msg, hwnd) {
    global gameButtons, hoveredBtn, themeName, btnSuspend

    ; Only react when OUR gui is active (prevents weirdness system-wide)
    if (WinActive("ahk_id " gui.Hwnd) = 0)
        return

    MouseGetPos , , &winHwnd, &ctrlHwnd, 2
    if (winHwnd != gui.Hwnd) {
        ClearHoveredButton()
        return
    }

    ; Arm tooltip for any control that has one
    ArmTooltip(gui, ctrlHwnd)

    ; Find which of our "game buttons" matches ctrlHwnd
    found := 0
    for _, b in gameButtons {
        if (b.Hwnd = ctrlHwnd) {
            found := b
            break
        }
    }

    if (!found) {
        ClearHoveredButton()
        return
    }

    ; Don't apply hover highlighting to the Suspend button.
    ; It has a persistent ON/OFF state color (green/red) that should not be overwritten by hover redraws.
    if (IsSet(btnSuspend) && btnSuspend && found.Hwnd = btnSuspend.Hwnd) {
        ClearHoveredButton()
        return
    }

    ; Already hovered? do nothing
    if (IsSet(hoveredBtn) && hoveredBtn && hoveredBtn.Hwnd = found.Hwnd)
        return

    ; Switch hover target
    SetHoveredButton(found)
}

SetHoveredButton(btn) {
    global hoveredBtn, themeName
    pal := GetThemePalette(themeName)

    ; Unhover previous
    ClearHoveredButton()

    hoveredBtn := btn

    ; Hover look (subtle)
    ; slightly brighter/different from panel
    try btn.Opt("Background" pal["accent2"])
    try btn.SetFont("c" pal["btnHighlightText"])
}

ClearHoveredButton() {
    global hoveredBtn, themeName
    HideTooltip()
    if (!IsSet(hoveredBtn) || !hoveredBtn)
        return

    pal := GetThemePalette(themeName)

    ; Back to normal
    try hoveredBtn.Opt("Background" pal["panel"])
    try hoveredBtn.SetFont("c" pal["text"])

    hoveredBtn := 0
}

SetStatus(msg, ms := 1500) {
    global txtStatus, themeName
    if !IsSet(txtStatus)
        return

    txtStatus.Text := msg
    try txtStatus.Visible := true

    ; clear after ms
    SetTimer(ClearStatus, -ms)
}

ClearStatus() {
    global txtStatus
    if !IsSet(txtStatus)
        return
    txtStatus.Text := ""
    try txtStatus.Visible := false
}

FlashCtrl(ctrl, ms := 120) {
    global themeName
    pal := GetThemePalette(themeName)

    flash := (themeName = "Bloodcraft") ? pal["accent"] : "DDDDDD"
    normal := pal.Has("btnBg") ? pal["btnBg"] : pal["panel"]

    try ctrl.Opt("Background" flash)

    SetTimer(() => ResetCtrlBackground(ctrl, normal), -ms)
}

ResetCtrlBackground(ctrl, color) {
    try ctrl.Opt("Background" color)
}

; =========================
; GUI
; =========================
BuildGui() {
    global mainGui, lv
    global edtSearch, ddlProfile, btnProfileMenu, btnSuspend, chkGameOnly
    global edtHotkey, ddlAction, chkEnabled, edtCommands
    global edtChatKey, edtDelay
    global chatKey, sendDelay, themeName, btnTheme
    global hdrBar, hdrTitle, btnMin, btnClose, hdrSep, titleBarH
    global txtFooter
    global themedText, themedInputs, themedOther
    global picLogo
    global y0, y0Offset
    global picThemeIcon

    ; Reset theming buckets (prevents duplicates if you ever rebuild the GUI)
    themedText := []
    themedInputs := []
    themedOther := []

    ; Borderless window (custom title bar)
    mainGui := Gui("-Caption +Border", APP_NAME " " APP_VERSION)
    mainGui.SetFont("s10")

    ; Move Save INI, Load INI, Rebind Hotkeys, Add, Update, Delete as one unit with a single y0 offset

    ; ---- Custom Bloodcraft Title Bar ----
    hdrBar := mainGui.AddText("x0 y0 w640 h" titleBarH " 0x200", "")

    if FileExist(gTitleLogoPath) {
        picLogo := mainGui.AddPicture("x10 y1 w38 h32 +BackgroundTrans", gTitleLogoPath)
    } else {
        picLogo := ""  ; sentinel (non-control)
    }

    hdrTitle := mainGui.AddText("x12 y7 w520 h20 0x200", APP_NAME " " APP_VERSION)
    hdrTitle.SetFont("s12 bold")

    btnMin := mainGui.AddButton("x640 y6 w30 h22", "–")
    btnClose := mainGui.AddButton("x676 y6 w30 h22", "X")
    AddTooltip(btnMin, "Minimize window")
    AddTooltip(btnClose, "Close app")
    btnMin.OnEvent("Click", (*) => WinMinimize("ahk_id " mainGui.Hwnd))
    btnClose.OnEvent("Click", (*) => ExitApp())

    hdrBar.OnEvent("Click", (*) => DragWindow(mainGui.Hwnd))
    hdrTitle.OnEvent("Click", (*) => DragWindow(mainGui.Hwnd))

    hdrSep := mainGui.AddText("x0 y" titleBarH " w960 h2", "")

    ; ---- Settings row ----
    t := mainGui.AddText("x10 y" y0 + 4 " w70", "Chat Key:")
    themedText.Push(t)

    edtChatKey := mainGui.AddEdit("x75 y" y0 + 2 " w90", chatKey)
    themedInputs.Push(edtChatKey)

    t := mainGui.AddText("x180 y" y0 + 4 " w90", "Delay (ms):")
    themedText.Push(t)

    edtDelay := mainGui.AddEdit("x255 y" y0 + 2 " w70", sendDelay)
    themedInputs.Push(edtDelay)

    ; Auto-apply settings shortly after you stop typing
    edtChatKey.OnEvent("Change", (*) => ScheduleSettingsApply())
    edtDelay.OnEvent("Change", (*) => ScheduleSettingsApply())

    btnApplySettings := CreateGameButton(mainGui, 360, y0 + 2, 90, 24, "Apply", (*) => ApplySettings())

    ; ---- Safety / QoL toggles ----
    btnSuspend := CreateGameButton(mainGui, 460, y0 + 2, 110, 24, "", (*) => ToggleSuspend())
    UpdateSuspendButtonText()
    AddTooltip(btnSuspend, "Suspend Macros`n`nDisables all macro hotkeys without closing the app.")

    chkGameOnly := mainGui.AddCheckBox("x585 y" y0 + 5 " w18 h18", "")
    chkGameOnly.Value := gGameFocusOnly ? 1 : 0
    themedOther.Push(chkGameOnly)

    txtGameOnly := mainGui.AddText("x607 y" y0 + 4 " w120", "V Rising only")
    themedText.Push(txtGameOnly)

    SetGameOnlyFromUI := (*) => (
        gGameFocusOnly := (chkGameOnly.Value = 1),
        SetStatus(gGameFocusOnly ? "Game focus safety: ON" : "Game focus safety: OFF"),
        ScheduleSettingsApply()
    )

    ToggleGameOnlyFromLabel := (*) => (
        chkGameOnly.Value := chkGameOnly.Value ? 0 : 1,
        SetGameOnlyFromUI()
    )

    chkGameOnly.OnEvent("Click", SetGameOnlyFromUI)
    txtGameOnly.OnEvent("Click", ToggleGameOnlyFromLabel)

    AddTooltip(chkGameOnly, "Game focus safety`n`nWhen enabled, macros only run while V Rising is the active window.")
    AddTooltip(txtGameOnly, "Game focus safety`n`nWhen enabled, macros only run while V Rising is the active window.")

    btnTheme := CreateGameButton(mainGui, 867, y0 + 2, 85, 24, "", (*) => ToggleTheme())
    picThemeIcon := mainGui.AddPicture("x" (840) " y" (y0 - 2) " w32 h32 +BackgroundTrans", themeIconBlood)
    ; btnTheme := CreateGameButton(mainGui, 840, y0 + 2, 85, 24, "", (*) => ToggleTheme())
    ; picThemeIcon := mainGui.AddPicture("x" (925) " y" (y0 - 2) " w32 h32 +BackgroundTrans", themeIconBlood)

    picThemeIcon.OnEvent("Click", (*) => ToggleTheme())

    UpdateThemeButtonText()

    ; Tooltips
    AddTooltip(btnApplySettings,
        "Apply`n`nApplies Chat Key + Delay immediately.`n(Also auto-applies after you stop typing.)")
    AddTooltip(btnTheme, "Toggle Theme`n`nSwitch between Dark Mode and Light Mode.")

    sepTop := mainGui.AddText("x10 y" y0 + 34 " w944 h1", "")
    global uiSepTop := sepTop

    sepMid := mainGui.AddText("x458 y" y0 + 42 " w1 h300", "")
    global uiSepMid := sepMid

    ; ---- ListView of binds ----
    ; ---- Profiles + Search / Filter ----
    t := mainGui.AddText("x10 y" y0 + 42 " w48", "Profile:")
    themedText.Push(t)

    ddlProfile := mainGui.AddDropDownList("x60 y" y0 + 40 " w130 Choose1", [])
    themedOther.Push(ddlProfile)
    ddlProfile.OnEvent("Change", (*) => OnProfileDropdownChanged())

    btnProfileMenu := CreateGameButton(mainGui, 195, y0 + 40, 70, 24, "Manage", (*) => ShowProfileMenu())
    AddTooltip(btnProfileMenu, "Profiles`n`nCreate / rename / duplicate / delete profiles.")

    t := mainGui.AddText("x275 y" y0 + 42 " w55", "Search:")
    themedText.Push(t)

    edtSearch := mainGui.AddEdit("x330 y" y0 + 40 " w120", "")
    themedInputs.Push(edtSearch)
    edtSearch.OnEvent("Change", (*) => RefreshListView())
    AddTooltip(edtSearch, "Search / Filter`n`nType to filter by hotkey, action, or command text.`nShortcut: Ctrl+F")

    ; Populate profile dropdown after control exists
    RefreshProfileDropdown(true)
    lv := mainGui.AddListView("x10 y" y0 + 66 " w440 h280 -Multi", ["On", "Hotkey", "Action", "Commands (preview)"])
    lv.Opt("+Grid")
    lv.OnEvent("Click", (*) => LoadSelectedIntoEditor())

    ; ---- Editor panel ----
    t := mainGui.AddText("x465 y" y0 + 46 " w60", "Hotkey:")
    themedText.Push(t)

    edtHotkey := mainGui.AddEdit("x525 y" y0 + 46 " w180", "")
    themedInputs.Push(edtHotkey)

    t := mainGui.AddText("x465 y" y0 + 76 " w60", "Action:")
    themedText.Push(t)

    ddlAction := mainGui.AddDropDownList("x525 y" y0 + 74 " w180", ["SendChat", "PrefillChat"])
    themedOther.Push(ddlAction)

    ; --- Right-side Action Help panel (keeps editor compact) ---
    ; Shows context/help without pushing the editor controls downward.
    global txtActionHelp, lblHelpTitle, sepHelp
    sepHelp := mainGui.AddText("x715 y" y0 + 42 " w1 h300", "")
    global uiSepHelp := sepHelp
    themedText.Push(sepHelp)

    lblHelpTitle := mainGui.AddText("x725 y" y0 + 46 " w220", "Action Help")
    lblHelpTitle.SetFont("s9 bold")
    themedText.Push(lblHelpTitle)

    txtActionHelp := mainGui.AddText("x725 y" y0 + 68 " w220 h120 +Border", "")
    txtActionHelp.SetFont("s9")
    themedText.Push(txtActionHelp)

    logoPath := A_ScriptDir "\assets\bloodcraft_resized.ico"  ; prefer PNG for in-panel logo
    if FileExist(logoPath) {
        ; Position under Action Help box (adjust x/y/w/h to taste)
        picHelpLogo := mainGui.AddPicture("x725 y" y0 + 200 " w220 h180 +BackgroundTrans", logoPath)

        ; Optional: clicking logo opens support menu
        picHelpLogo.OnEvent("Click", ShowSupportMenu)
        picHelpLogo.OnEvent("ContextMenu", ShowSupportMenu)
    }

    ddlAction.OnEvent("Change", (*) => UpdateActionHelpText())
    UpdateActionHelpText()

    ; Enabled (moved up now that helper text is on the right)
    chkEnabled := mainGui.AddCheckbox("x525 y" y0 + 104 " w24", " ")
    themedOther.Push(chkEnabled)
    chkEnabled.Value := 1

    lblEnabled := mainGui.AddText("x550 y" y0 + 104 " w120", "Enabled")
    themedText.Push(lblEnabled)

    t := mainGui.AddText("x465 y" y0 + 130 " w240", "Commands (one per line):")
    themedText.Push(t)

    ; Taller commands box (reclaimed vertical space)
    edtCommands := mainGui.AddEdit("x465 y" y0 + 150 " w240 h198 -Wrap +VScroll", "")
    themedInputs.Push(edtCommands)

    ; ---- Buttons ----

    btnAdd := CreateGameButton(mainGui, 465, y0 + y0Offset, 75, 24, "Add", (*) => AddBindingFromEditor(),
    "Added new binding")
    btnUpdate := CreateGameButton(mainGui, 545, y0 + y0Offset, 75, 24, "Update", (*) => UpdateBindingFromEditor(),
    "Updated binding")
    btnDelete := CreateGameButton(mainGui, 625, y0 + y0Offset, 80, 24, "Delete", (*) => DeleteSelected(),
    "Deleted selected binding")

    AddTooltip(btnAdd, "Add`n`nCreates a NEW binding using the editor fields on the right.")
    AddTooltip(btnUpdate, "Update`n`nOverwrites the selected row using the editor fields on the right.")
    AddTooltip(btnDelete, "Delete`n`nRemoves the selected binding row.")

    btnSave := CreateGameButton(mainGui, 10, y0 + y0Offset, 90, 24, "Save", (*) => SaveCurrentProfile(),
    "Profile saved")
    btnLoad := CreateGameButton(mainGui, 105, y0 + y0Offset, 90, 24, "Reload", (*) => (LoadCurrentProfile(),
    RefreshListView(), RegisterAllHotkeys()),
    "Profile reloaded")
    btnRebind := CreateGameButton(mainGui, 200, y0 + y0Offset, 120, 24, "Rebind Hotkeys", (*) => (ApplySettings(),
    RegisterAllHotkeys()))

    btnMoveUp := CreateGameButton(mainGui, 330, y0 + y0Offset, 55, 24, "▲ Up", (*) => MoveSelected(-1))
    btnMoveDown := CreateGameButton(mainGui, 390, y0 + y0Offset, 60, 24, "▼ Down", (*) => MoveSelected(1))
    AddTooltip(btnMoveUp, "Move Up`n`nMoves the selected macro up in the list.")
    AddTooltip(btnMoveDown, "Move Down`n`nMoves the selected macro down in the list.")
    themedOther.Push(btnMoveUp), themedOther.Push(btnMoveDown)

    AddTooltip(btnSave, "Save Profile`n`nSaves bindings + settings to the current profile INI in \profiles\.")
    AddTooltip(btnLoad,
        "Reload Profile`n`nReloads bindings + settings from the current profile INI in \profiles\ (discarding unsaved changes)."
    )
    AddTooltip(btnRebind, "Rebind Hotkeys`n`nRe-registers enabled hotkeys. Use this if hotkeys stop responding.")

    themedOther.Push(btnSave), themedOther.Push(btnLoad), themedOther.Push(btnRebind)

    btnSave.OnEvent("Click", (*) => (ApplySettings(), SaveToIni()))
    btnLoad.OnEvent("Click", (*) => (LoadFromIni(), SyncUiFromSettings(), RefreshListView(), ApplySettings(false),
    RegisterAllHotkeys(),
    ApplyTheme()))
    btnRebind.OnEvent("Click", (*) => (ApplySettings(), RegisterAllHotkeys()))

    sepBottom := mainGui.AddText("x10 y" y0 + y0Offset + 34 " w944 h1", "")
    global uiSepBottom := sepBottom

    ; Footer (created BEFORE ApplyTheme so it's styled)
    txtFooter := mainGui.AddText("x10 y" y0 + y0Offset + 36 " w500", "Created by Navist • AI-assisted")
    themedText.Push(txtFooter)

    ; Bottom-right status text (starts hidden)
    txtStatus := mainGui.AddText("x520 y" y0 + y0Offset + 36 " w190 Right", "")
    themedText.Push(txtStatus)
    txtStatus.Visible := false

    iconDir := A_ScriptDir "\icons\"
    picSupport := mainGui.AddPicture("x765 y" y0 + y0Offset + 36 " w20 h18 +BackgroundTrans", iconDir "support_heart.png"
    )
    picSupport.OnEvent("Click", ShowSupportMenu)
    picSupport.OnEvent("ContextMenu", ShowSupportMenu)

    txtSupport := mainGui.AddText("x790 y" y0 + y0Offset + 36 " w95 Center cRed", "Support Navist")
    txtSupport.SetFont("Underline")
    txtSupport.OnEvent("Click", ShowSupportMenu)
    txtSupport.OnEvent("ContextMenu", ShowSupportMenu)

    mainGui.OnEvent("Close", (*) => ExitApp())

    ApplyTheme()
    mainGui.OnEvent("Size", GuiResized)
    mainGui.Show("w960 h450")
    ; Ctrl+F focuses the Search box (while the window is active)
    HotIfWinActive("ahk_id " mainGui.Hwnd)
    Hotkey "^f", (*) => FocusSearch(), "On"
    HotIf
    EnableButtonHover(mainGui)
    ForceBorderless(mainGui.Hwnd)
    RemoveDwmFrame(mainGui.Hwnd)
    ; after mainGui.Show(...) / ForceBorderless / RemoveDwmFrame
    if IsSet(picHelpLogo) {
        try picHelpLogo.MoveDraw(picHelpLogo.X, picHelpLogo.Y, picHelpLogo.W, picHelpLogo.H)
    }

}

LayoutTitlebar(w, h) {
    global hdrBar, hdrSep, hdrTitle, btnMin, btnClose, titleBarH, picLogo

    safe := 88

    ; bar + separator
    try hdrBar.Move(0, 0, w - safe, titleBarH)
    try hdrSep.Move(0, titleBarH, w, 2)

    ; logo + title
    if (picLogo && IsObject(picLogo)) {
        try picLogo.Move(10, 1, 38, 32)
        try hdrTitle.Move(48, 7, w - (safe + 60), 20)
    } else {
        try hdrTitle.Move(12, 7, w - (safe + 24), 20)
    }

    ; window buttons
    try btnMin.Move(w - 80, 6, 30, 22)
    try btnClose.Move(w - 44, 6, 30, 22)
}

GuiResized(thisGui, minMax, w, h) {
    LayoutTitlebar(w, h)
}

UpdateThemeButtonText() {
    global btnTheme, themeName
    global picThemeIcon, themeIconBlood, themeIconRest

    if !IsSet(btnTheme)
        return

    if (themeName = "Bloodcraft") {
        btnTheme.Text := "Hunt Mode"
        if IsSet(picThemeIcon)
            picThemeIcon.Value := themeIconBlood
    } else {
        btnTheme.Text := "Rest Mode"
        if IsSet(picThemeIcon)
            picThemeIcon.Value := themeIconRest
    }
}

ForceBorderless(hwnd) {
    ; Remove WS_CAPTION (0x00C00000)
    try WinSetStyle("-0xC00000", "ahk_id " hwnd)
    WinRedraw("ahk_id " hwnd)
}

RemoveDwmFrame(hwnd) {
    ; Tell DWM to not draw a window frame border
    ; DWMWA_WINDOW_CORNER_PREFERENCE = 33 (Win11 rounding), we can set to default (0)
    ; DWMWA_NCRENDERING_POLICY = 2 (disabled) sometimes helps
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 2, "int*", 2, "int", 4)  ; DWMWA_NCRENDERING_POLICY=2
    WinRedraw("ahk_id " hwnd)
}
; =========================
; UI logic
; =========================
RefreshListView() {
    global lv, bindings, lvIndexMap, edtSearch
    lv.Delete()
    lvIndexMap := []

    filter := ""
    if IsSet(edtSearch)
        filter := StrLower(Trim(edtSearch.Text))

    loop bindings.Length {
        i := A_Index
        b := bindings[i]

        preview := ""
        if (b.commands.Length >= 1) {
            preview := b.commands[1]
            if (b.commands.Length > 1)
                preview .= "  (+" (b.commands.Length - 1) " more)"
        }

        if (filter != "") {
            hay := StrLower(b.hotkey " " b.action " " preview)
            ; also search full command list (best-effort)
            if (b.commands.Length > 1) {
                for _, c in b.commands
                    hay .= " " StrLower(c)
            }
            if !InStr(hay, filter)
                continue
        }

        lv.Add("", b.enabled ? "✓" : "", b.hotkey, b.action, preview)
        lvIndexMap.Push(i)
    }

    lv.ModifyCol(1, 35)
    lv.ModifyCol(2, 80)
    lv.ModifyCol(3, 110)
    lv.ModifyCol(4, 200)
}

GetSelectedRow() {
    global lv
    return lv.GetNext(0)
}

GetSelectedBindingIndex() {
    global lvIndexMap
    row := GetSelectedRow()
    if (!row)
        return 0
    ; If filtering is active, map LV row -> binding index
    if (IsSet(lvIndexMap) && lvIndexMap.Length >= row)
        return lvIndexMap[row]
    return row
}

SelectBindingInList(bindingIndex) {
    global lv, lvIndexMap
    if (bindingIndex < 1)
        return
    ; find matching row in current list
    row := 0
    if (IsSet(lvIndexMap) && lvIndexMap.Length) {
        loop lvIndexMap.Length {
            if (lvIndexMap[A_Index] = bindingIndex) {
                row := A_Index
                break
            }
        }
    } else {
        row := bindingIndex
    }
    if (row)
        lv.Modify(row, "Select Focus Vis")
}

LoadSelectedIntoEditor() {
    global bindings
    global edtHotkey, ddlAction, chkEnabled, edtCommands

    idx := GetSelectedBindingIndex()
    if (!idx)
        return

    b := bindings[idx]

    edtHotkey.Text := b.hotkey

    ddlAction.Text := b.action
    chkEnabled.Value := b.enabled ? 1 : 0

    ; IMPORTANT: show all commands, one per line
    edtCommands.Value := CommandsToBlock(b.commands)
}

ReadEditorBinding() {
    global edtHotkey, ddlAction, chkEnabled, edtCommands

    hk := Trim(edtHotkey.Text)
    action := ddlAction.Text
    enabled := chkEnabled.Value = 1

    cmds := ParseCommands(edtCommands.Text)

    if (hk = "")
        throw Error("Hotkey is required.")

    switch action {
        case "SendChat", "PrefillChat":
            if (cmds.Length < 1)
                throw Error(action " needs at least 1 command line.")
        default:
            throw Error("Unknown action: " action)
    }

    return { enabled: enabled, hotkey: hk, action: action, commands: cmds }
}

AddBindingFromEditor() {
    global bindings
    try {
        b := ReadEditorBinding()

        ; Warn only if the NEW binding is enabled and conflicts with another enabled binding.
        dup := FindDuplicateHotkey(b.hotkey)
        if (dup) {
            other := bindings[dup]
            if (b.enabled && other.enabled) {
                msg :=
                    (
                        "Duplicate hotkey detected:`n`n"
                        "Hotkey: " b.hotkey "`n"
                        "Existing row: " dup " (" other.action ")`n"
                        "Existing commands: " PreviewBinding(other) "`n`n"
                        "Continue anyway?"
                    )
                if (MsgBox(msg, "Duplicate Hotkey", "YesNo Icon!") != "Yes")
                    return
            }
        }

        bindings.Push(b)
        RefreshListView()
        RegisterAllHotkeys()
        SaveToIni()
    } catch as e {
        MsgBox e.Message, "Add Binding", "Icon!"
    }
}

UpdateBindingFromEditor() {
    global bindings, lv
    idx := GetSelectedBindingIndex()
    if (!idx) {
        MsgBox "Select a binding to update.", "Update Binding", "Icon!"
        return
    }

    try {
        b := ReadEditorBinding()

        dup := FindDuplicateHotkey(b.hotkey, idx)
        if (dup) {
            other := bindings[dup]
            if (b.enabled && other.enabled) {
                msg :=
                    (
                        "Duplicate hotkey detected:`n`n"
                        "Hotkey: " b.hotkey "`n"
                        "Existing row: " dup " (" other.action ")`n"
                        "Existing commands: " PreviewBinding(other) "`n`n"
                        "Continue anyway?"
                    )
                if (MsgBox(msg, "Duplicate Hotkey", "YesNo Icon!") != "Yes")
                    return
            }
        }

        bindings[idx] := b
        RefreshListView()
        RegisterAllHotkeys()
        SaveToIni()
        lv.Modify(idx, "Select Focus")
    } catch as e {
        MsgBox e.Message, "Update Binding", "Icon!"
    }
}

DeleteSelected() {
    global bindings
    idx := GetSelectedBindingIndex()
    if (!idx) {
        MsgBox "Select a binding to delete.", "Delete Binding", "Icon!"
        return
    }

    if (MsgBox("Delete selected binding?", "Confirm", "YesNo Icon?") = "Yes") {
        bindings.RemoveAt(idx)
        RefreshListView()
        RegisterAllHotkeys()
        SaveToIni()
    }
}

; =========================
; Bootstrap (seed defaults)
; =========================
SeedDefaultsIfEmpty() {
    global bindings
    if (bindings.Length > 0)
        return

    bindings := []
    bindings.Push({ enabled: true, hotkey: "F1", action: "PrefillChat", commands: ['.stp tpr '] })
    bindings.Push({ enabled: true, hotkey: "F2", action: "PrefillChat", commands: ['.stp tpa '] })
    bindings.Push({ enabled: true, hotkey: "F3", action: "SendChat", commands: ['.stash', '.pull "Blood Essence" 200'] })
    bindings.Push({ enabled: true, hotkey: "F4", action: "SendChat", commands: ['.stp tp shop'] })
    bindings.Push({ enabled: true, hotkey: "F5", action: "SendChat", commands: ['.stp tp home'] })
    bindings.Push({ enabled: true, hotkey: "F7", action: "SendChat", commands: [
        '.pull "Enchanted Brew" 4',
        '.pull "Brew of Ferocity" 4',
        '.pull "Potion of Rage" 4',
        '.pull "Witch Potion" 4',
        '.pull "Storm Coating" 2',
        '.pull "Blood Coating" 2'
    ] })

    bindings.Push({ enabled: true, hotkey: "F8", action: "SendChat", commands: ['.prestige sb'] })
    bindings.Push({ enabled: true, hotkey: "F9", action: "SendChat", commands: ['.fam sb styx'] })
    bindings.Push({ enabled: true, hotkey: "F10", action: "SendChat", commands: ['.fam sb lucile'] })
    bindings.Push({ enabled: true, hotkey: "F11", action: "SendChat", commands: ['.fam sb solarus'] })

    bindings.Push({ enabled: true, hotkey: "^F1", action: "SendChat", commands: ['.pull "Blood Essence" 9999'] })
    bindings.Push({ enabled: true, hotkey: "+F1", action: "SendChat", commands: ['.pull "Plant Fibre" 9999'] })
}

; Load profiles / config
InitProfiles()

; Load current profile if it exists, otherwise seed defaults into Default profile
if (!LoadCurrentProfile()) {
    SeedDefaultsIfEmpty()
    SaveCurrentProfile()
}

BuildGui()
; Tray menu
try {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open", (*) => (mainGui.Show(), WinActivate("ahk_id " mainGui.Hwnd)))
    A_TrayMenu.Add("Suspend Macros", (*) => ToggleSuspend())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    if (gSuspended)
        A_TrayMenu.Check("Suspend Macros")
}
RefreshListView()
RegisterAllHotkeys()

ShowSupportMenu(*) {
    global mainGui, supportPopupHwnd, supportHookInstalled

    static supportGui := 0
    static iconDir := A_ScriptDir "\icons\"
    static popupW := 170
    static rowH := 26
    static padX := 10
    static padY := 10

    ; Create once
    if !supportGui {
        supportGui := Gui("-Caption +ToolWindow +AlwaysOnTop")
        supportGui.BackColor := "202020"

        ; Attach to main window so it stays on top of it
        try supportGui.Opt("+Owner" mainGui.Hwnd)

        y := padY

        AddItem(name, iconFile, url) {

            pic := supportGui.AddPicture("x" padX " y" y " w16 h16 +BackgroundTrans", iconFile)
            txt := supportGui.AddText("x" (padX + 24) " y" (y - 2) " w" (popupW - (padX + 34)) " cWhite", name)

            ; Clicks open link and close popup
            pic.OnEvent("Click", (*) => (Run(url), supportGui.Hide()))
            txt.OnEvent("Click", (*) => (Run(url), supportGui.Hide()))

            ; Right click also opens link
            pic.OnEvent("ContextMenu", (*) => (Run(url), supportGui.Hide()))
            txt.OnEvent("ContextMenu", (*) => (Run(url), supportGui.Hide()))

            y += rowH
        }

        AddItem("PayPal", iconDir "paypal.png", "https://www.paypal.com/paypalme/Navist")
        AddItem("Patreon", iconDir "patreon.png", "https://www.patreon.com/cw/Navist")
        AddItem("Ko-Fi", iconDir "kofi.png", "https://ko-fi.com/Navist")
        AddItem("GitHub", iconDir "github.png", "https://github.com/Navist")

        ; Remember hwnd for click-away handler
        supportPopupHwnd := supportGui.Hwnd

        ; Let Esc close it (supported GUI event)
        supportGui.OnEvent("Escape", (*) => supportGui.Hide())

        ; Install click-away handler once
        if !supportHookInstalled {
            supportHookInstalled := true
            OnMessage(0x201, SupportPopup_ClickAway) ; WM_LBUTTONDOWN
            OnMessage(0x204, SupportPopup_ClickAway) ; WM_RBUTTONDOWN
            OnMessage(0x1C, SupportPopup_ActivateApp) ; WM_ACTIVATEAPP (close when clicking outside the app)
        }

        ; Pre-calc size (AutoSize) once
        supportGui.Show("Hide AutoSize")
    }

    ; Toggle: if already visible, hide and stop
    try {
        if DllCall("IsWindowVisible", "ptr", supportGui.Hwnd, "int") {
            supportGui.Hide()
            return
        }
    }

    ; Show in a consistent place near the bottom-right of main window
    mainGui.GetPos(&gx, &gy, &gw, &gh)

    px := gx + gw - (popupW + 30)
    py := gy + gh - 155  ; above footer/support link area

    supportGui.Show("x" px " y" py " NA")
}

SupportPopup_ClickAway(wParam, lParam, msg, hwnd) {
    global supportPopupHwnd

    if !supportPopupHwnd
        return

    ; If click happened inside the popup, don't hide
    MouseGetPos(, , &winHwnd)
    if (winHwnd = supportPopupHwnd)
        return

    ; Otherwise hide popup
    try WinHide("ahk_id " supportPopupHwnd)
}

SupportPopup_ActivateApp(wParam, lParam, msg, hwnd) {
    ; Close the support popup when the app loses activation (clicking outside the window, alt-tab, etc.)
    global supportPopupHwnd

    if !supportPopupHwnd
        return

    ; wParam = 0 when deactivated, 1 when activated
    if (wParam = 0) {
        try WinHide("ahk_id " supportPopupHwnd)
    }
}
