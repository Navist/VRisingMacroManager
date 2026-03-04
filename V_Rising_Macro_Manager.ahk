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

global iniPath := A_ScriptDir "\vrising_macros.ini"

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
global picSupport
global txtSupport
global supportPopupHwnd := 0
global supportHookInstalled := false
global txtStatus
global statusTimerRunning := false
global APP_NAME := "V Rising Macro Manager"
global APP_VERSION := "v2.3.0"
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
SaveToIni() {
    global iniPath, bindings, chatKey, sendDelay, themeName

    try FileDelete iniPath

    IniWrite chatKey, iniPath, "Settings", "chatKey"
    IniWrite sendDelay, iniPath, "Settings", "sendDelay"
    IniWrite themeName, iniPath, "Settings", "theme"
    IniWrite bindings.Length, iniPath, "Meta", "count"

    loop bindings.Length {
        b := bindings[A_Index]
        section := "Bind" A_Index

        IniWrite b.enabled ? 1 : 0, iniPath, section, "enabled"
        IniWrite b.hotkey, iniPath, section, "hotkey"
        IniWrite b.action, iniPath, section, "action"

        ; Store commands safely as cmdCount + cmd1..cmdN
        IniWrite b.commands.Length, iniPath, section, "cmdCount"
        loop b.commands.Length {
            IniWrite b.commands[A_Index], iniPath, section, "cmd" A_Index
        }
    }
}

LoadFromIni() {
    global iniPath, bindings, chatKey, sendDelay, themeName

    if !FileExist(iniPath)
        return false

    chatKey := IniRead(iniPath, "Settings", "chatKey", chatKey)
    sendDelay := IniRead(iniPath, "Settings", "sendDelay", sendDelay)
    themeName := IniRead(iniPath, "Settings", "theme", themeName)

    count := (IniRead(iniPath, "Meta", "count", 0) + 0)
    bindings := []

    loop count {
        section := "Bind" A_Index

        enabled := (IniRead(iniPath, section, "enabled", 1) + 0)
        hk := IniRead(iniPath, section, "hotkey", "")
        action := IniRead(iniPath, section, "action", "SendChat")

        ; Preferred: cmdCount/cmd#
        cmdCount := (IniRead(iniPath, section, "cmdCount", 0) + 0)
        cmds := []

        if (cmdCount > 0) {
            loop cmdCount {
                c := IniRead(iniPath, section, "cmd" A_Index, "")
                if (Trim(c) != "")
                    cmds.Push(c)
            }
        } else {
            ; Fallback: legacy multiline "commands" key (best-effort)
            block := IniRead(iniPath, section, "commands", "")
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
    global gameButtons, hoveredBtn, themeName

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
    global edtHotkey, ddlAction, chkEnabled, edtCommands
    global edtChatKey, edtDelay
    global chatKey, sendDelay, themeName, btnTheme
    global hdrBar, hdrTitle, btnMin, btnClose, hdrSep, titleBarH
    global txtFooter
    global themedText, themedInputs, themedOther
    global picLogo
    global y0, y0Offset

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
    btnTheme := CreateGameButton(mainGui, 465, y0 + 2, 160, 24, "", (*) => ToggleTheme())
    UpdateThemeButtonText()

    ; Tooltips
    AddTooltip(btnApplySettings,
        "Apply`n`nApplies Chat Key + Delay immediately.`n(Also auto-applies after you stop typing.)")
    AddTooltip(btnTheme, "Toggle Theme`n`nSwitch between Bloodcraft Dark and Light Mode.")

    sepTop := mainGui.AddText("x10 y" y0 + 34 " w944 h1", "")
    global uiSepTop := sepTop

    sepMid := mainGui.AddText("x458 y" y0 + 42 " w1 h300", "")
    global uiSepMid := sepMid

    ; ---- ListView of binds ----
    lv := mainGui.AddListView("x10 y" y0 + 46 " w440 h300 -Multi", ["On", "Hotkey", "Action", "Commands (preview)"])
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

    btnSave := CreateGameButton(mainGui, 10, y0 + y0Offset, 90, 24, "Save INI", (*) => SaveToIni(), "Saved to INI")
    btnLoad := CreateGameButton(mainGui, 105, y0 + y0Offset, 90, 24, "Load INI", (*) => LoadFromIni(),
    "Loaded from INI")
    btnRebind := CreateGameButton(mainGui, 200, y0 + y0Offset, 120, 24, "Rebind Hotkeys", (*) => (ApplySettings(),
    RegisterAllHotkeys()))

    AddTooltip(btnSave, "Save INI`n`nSaves bindings + settings to vrising_macros.ini.")
    AddTooltip(btnLoad, "Load INI`n`nLoads bindings + settings from vrising_macros.ini.")
    AddTooltip(btnRebind, "Rebind Hotkeys`n`nRe-registers enabled hotkeys. Use this if hotkeys stop responding.")

    themedOther.Push(btnSave), themedOther.Push(btnLoad), themedOther.Push(btnRebind)

    btnSave.OnEvent("Click", (*) => (ApplySettings(), SaveToIni()))
    btnLoad.OnEvent("Click", (*) => (LoadFromIni(), RefreshListView(), ApplySettings(false), RegisterAllHotkeys(),
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
    if !IsSet(btnTheme)
        return
    btnTheme.Text := (themeName = "Bloodcraft")
        ? "🩸 Bloodcraft Dark: ON"
        : "☀️ Light Mode: ON"
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
    global lv, bindings
    lv.Delete()

    loop bindings.Length {
        b := bindings[A_Index]
        preview := ""
        if (b.commands.Length >= 1) {
            preview := b.commands[1]
            if (b.commands.Length > 1)
                preview .= "  (+" (b.commands.Length - 1) " more)"
        }
        lv.Add("", b.enabled ? "✓" : "", b.hotkey, b.action, preview)
    }
    lv.ModifyCol(1, 35)
    lv.ModifyCol(2, 80)
    lv.ModifyCol(3, 110)
    lv.ModifyCol(4, 200)
}

GetSelectedIndex() {
    global lv
    return lv.GetNext(0)
}

LoadSelectedIntoEditor() {
    global bindings
    global edtHotkey, ddlAction, chkEnabled, edtCommands

    idx := GetSelectedIndex()
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
    idx := GetSelectedIndex()
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
    idx := GetSelectedIndex()
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

; Load config if exists, otherwise seed defaults
if (!LoadFromIni())
    SeedDefaultsIfEmpty()

BuildGui()
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
    MouseGetPos , , &winHwnd
    if (winHwnd = supportPopupHwnd)
        return

    ; Otherwise hide popup
    try WinHide("ahk_id " supportPopupHwnd)
}
