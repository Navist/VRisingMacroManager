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
global iniPath := A_ScriptDir "\vrising_macros.ini"
if FileExist(A_ScriptDir "\bloodcraft_resized.ico")
    TraySetIcon(A_ScriptDir "\bloodcraft_resized.ico")

; Theming buckets
global themedText := []      ; text labels
global themedInputs := []    ; edit boxes
global themedOther := []     ; checkbox, ddl, buttons
global btnTheme  ; theme toggle button (needs text update on theme change)
global pnlLeft, pnlRight, accentLine
global hdrGlow  ; optional accent glow under title bar (only on Bloodcraft theme)

global gameButtons := []          ; holds the Text-controls that act like buttons
global hoveredBtn := 0            ; currently hovered control (GuiCtrl)

; Custom titlebar globals
global hdrBar, hdrTitle, btnMin, btnClose, hdrSep
global titleBarH := 34

; UI globals
global mainGui, lv
global edtHotkey, ddlAction, chkEnabled, edtCommands
global edtChatKey, edtDelay
global txtFooter
global picLogo
global txtStatus
global statusTimerRunning := false

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

PreSendChat(msg) {
    global chatKey, sendDelay
    if (msg = "")
        return
    Send "{" chatKey "}"
    Sleep sendDelay
    Send msg
}

GrabBuffs(lines) {
    global sendDelay
    for _, line in lines {
        if (Trim(line) != "")
            SendChat(line)
        Sleep sendDelay
    }
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
        case "SendChat":
            SendChat(cmds.Length >= 1 ? cmds[1] : "")
        case "PreSendChat":
            PreSendChat(cmds.Length >= 1 ? cmds[1] : "")
        case "StashNGrab":
            SendChat(cmds.Length >= 1 ? cmds[1] : "")
            Sleep sendDelay
            SendChat(cmds.Length >= 2 ? cmds[2] : "")
        case "GrabBuffs":
            GrabBuffs(cmds)
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
    global hdrBar, hdrTitle, btnMin, btnClose, hdrSep, btnTheme, hdrGlow
    global pnlLeft, pnlRight, accentLine
    global uiSepTop, uiSepMid, uiSepBottom

    pal := GetThemePalette(themeName)

    mainGui.BackColor := pal["bg"]
    mainGui.SetFont("s10 c" pal["text"], pal["font"])

    ; Panel styling
    if IsSet(pnlLeft)
        try pnlLeft.Opt("Background" pal["panel"])
    if IsSet(pnlRight)
        try pnlRight.Opt("Background" pal["panel"])
    if IsSet(accentLine)
        try accentLine.Opt("Background" pal["accent"])

    ; Divider color: muted in light, blood in bloodcraft (subtle)
    divCol := (themeName = "Bloodcraft") ? pal["accent2"] : pal["muted"]

    if IsSet(uiSepTop)
        try uiSepTop.Opt("Background" divCol)
    if IsSet(uiSepMid)
        try uiSepMid.Opt("Background" divCol)
    if IsSet(uiSepBottom)
        try uiSepBottom.Opt("Background" divCol)

    try pnlLeft.Opt("Border")
    try pnlRight.Opt("Border")

    ; Accent line (subtle)
    if (themeName = "Bloodcraft") {
        try accentLine.Opt("Background" pal["accent"])
    }
    else {
        try accentLine.Opt("Background" pal["accent2"])
    }

    if IsSet(hdrGlow) {
        if (themeName = "Bloodcraft") {
            try hdrGlow.Opt("Background" pal["accent2"])
        } else {
            try hdrGlow.Opt("Background" pal["panel"])
        }
    }

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
    global hdrBar, hdrTitle, btnMin, btnClose, hdrSep, titleBarH, hdrGlow
    global txtFooter
    global themedText, themedInputs, themedOther
    global picLogo
    ; global pnlLeft, pnlRight, accentLine

    ; Reset theming buckets (prevents duplicates if you ever rebuild the GUI)
    themedText := []
    themedInputs := []
    themedOther := []

    ; Borderless window (custom title bar)
    mainGui := Gui("+Resize -Caption +Border", "V Rising Macro Manager")
    mainGui.SetFont("s10")

    y0 := titleBarH + 8
    ; Background panels (these sit behind controls)
    pnlLeft := mainGui.AddText("x8 y" y0 + 34 " w448 h292", "")
    pnlRight := mainGui.AddText("x458 y" y0 + 34 " w254 h292", "")
    accentLine := mainGui.AddText("x8 y" y0 + 34 " w704 h2", "")

    ; ---- Custom Bloodcraft Title Bar ----
    hdrBar := mainGui.AddText("x0 y0 w640 h" titleBarH " 0x200", "")  ; stop before buttons
    logoPath := A_ScriptDir "\bloodcraft_resized.png"
    if FileExist(logoPath) {
        picLogo := mainGui.AddPicture("x10 y1 w32 h32", logoPath)
        hdrTitle := mainGui.AddText("x48 y7 w520 h20 0x200", "V Rising Macro Manager")
    } else {
        hdrTitle := mainGui.AddText("x12 y7 w520 h20 0x200", "V Rising Macro Manager")
    }
    hdrTitle.SetFont("s12 bold")

    btnMin := mainGui.AddButton("x640 y6 w30 h22", "–")
    btnClose := mainGui.AddButton("x676 y6 w30 h22", "X")
    btnMin.OnEvent("Click", (*) => WinMinimize("ahk_id " mainGui.Hwnd))
    btnClose.OnEvent("Click", (*) => ExitApp())

    hdrBar.OnEvent("Click", (*) => DragWindow(mainGui.Hwnd))
    hdrTitle.OnEvent("Click", (*) => DragWindow(mainGui.Hwnd))

    hdrSep := mainGui.AddText("x0 y" titleBarH " w720 h2", "")

    ; ---- Settings row ----
    t := mainGui.AddText("x10 y" y0 + 4 " w70", "Chat Key:")
    themedText.Push(t)

    edtChatKey := mainGui.AddEdit("x75 y" y0 + 2 " w90", chatKey)
    themedInputs.Push(edtChatKey)

    t := mainGui.AddText("x180 y" y0 + 4 " w90", "Delay (ms):")
    themedText.Push(t)

    edtDelay := mainGui.AddEdit("x255 y" y0 + 2 " w70", sendDelay)
    themedInputs.Push(edtDelay)

    btnApplySettings := CreateGameButton(mainGui, 360, y0 + 2, 90, 24, "Apply", (*) => ApplySettings())
    btnTheme := CreateGameButton(mainGui, 465, y0 + 2, 160, 24, "", (*) => ToggleTheme())
    UpdateThemeButtonText()

    sepTop := mainGui.AddText("x10 y" y0 + 34 " w704 h1", "")
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

    ddlAction := mainGui.AddDropDownList("x525 y" y0 + 74 " w180", ["SendChat", "PreSendChat", "StashNGrab",
        "GrabBuffs"])
    themedOther.Push(ddlAction)

    chkEnabled := mainGui.AddCheckbox("x525 y" y0 + 104 " w24", " ")
    themedOther.Push(chkEnabled)
    chkEnabled.Value := 1

    lblEnabled := mainGui.AddText("x550 y" y0 + 104 " w120", "Enabled")
    themedText.Push(lblEnabled)

    t := mainGui.AddText("x465 y" y0 + 136 " w240", "Commands (one per line):")
    themedText.Push(t)

    edtCommands := mainGui.AddEdit("x465 y" y0 + 156 " w240 h190 -Wrap +VScroll", "")
    themedInputs.Push(edtCommands)

    ; ---- Buttons ----

    btnAdd := CreateGameButton(mainGui, 465, y0 + 356, 75, 24, "Add", (*) => AddBindingFromEditor(),
    "Added new binding")
    btnUpdate := CreateGameButton(mainGui, 545, y0 + 356, 75, 24, "Update", (*) => UpdateBindingFromEditor(),
    "Updated binding")
    btnDelete := CreateGameButton(mainGui, 625, y0 + 356, 80, 24, "Delete", (*) => DeleteSelected(),
    "Deleted selected binding")

    btnSave := CreateGameButton(mainGui, 10, y0 + 356, 90, 24, "Save INI", (*) => SaveToIni(), "Saved to INI")
    btnLoad := CreateGameButton(mainGui, 105, y0 + 356, 90, 24, "Load INI", (*) => LoadFromIni(), "Loaded from INI")
    btnRebind := CreateGameButton(mainGui, 200, y0 + 356, 120, 24, "Rebind Hotkeys", (*) => (ApplySettings(),
    RegisterAllHotkeys()))

    themedOther.Push(btnSave), themedOther.Push(btnLoad), themedOther.Push(btnRebind)

    btnSave.OnEvent("Click", (*) => (ApplySettings(), SaveToIni()))
    btnLoad.OnEvent("Click", (*) => (LoadFromIni(), RefreshListView(), ApplySettings(false), RegisterAllHotkeys(),
    ApplyTheme()))
    btnRebind.OnEvent("Click", (*) => (ApplySettings(), RegisterAllHotkeys()))

    sepBottom := mainGui.AddText("x10 y" y0 + 390 " w704 h1", "")
    global uiSepBottom := sepBottom

    ; Footer (created BEFORE ApplyTheme so it's styled)
    txtFooter := mainGui.AddText("x10 y" y0 + 392 " w500", "Created by Navist • AI-assisted")
    themedText.Push(txtFooter)

    ; Bottom-right status text (starts hidden)
    txtStatus := mainGui.AddText("x520 y" y0 + 392 " w190 Right", "")
    themedText.Push(txtStatus)
    txtStatus.Visible := false

    mainGui.OnEvent("Close", (*) => ExitApp())

    ApplyTheme()
    mainGui.OnEvent("Size", GuiResized)
    mainGui.Show("w720 h450")
    EnableButtonHover(mainGui)
    ForceBorderless(mainGui.Hwnd)
    RemoveDwmFrame(mainGui.Hwnd)

}

GuiResized(thisGui, minMax, w, h) {
    global hdrBar, hdrSep, hdrGlow, hdrTitle, btnMin, btnClose, titleBarH
    global picLogo

    safe := 88

    try hdrBar.Move(0, 0, w - safe, titleBarH)
    try hdrSep.Move(0, titleBarH, w, 2)
    try hdrGlow.Move(0, titleBarH + 2, w, 1)

    if IsSet(picLogo) {
        try picLogo.Move(10, 1, 32, 32)
        try hdrTitle.Move(48, 7, w - (safe + 60), 20)
    } else {
        try hdrTitle.Move(12, 7, w - (safe + 24), 20)
    }

    try btnMin.Move(w - 80, 6, 30, 22)
    try btnClose.Move(w - 44, 6, 30, 22)
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
        case "SendChat", "PreSendChat":
            if (cmds.Length < 1)
                throw Error(action " needs at least 1 command line.")
        case "StashNGrab":
            if (cmds.Length < 2)
                throw Error("StashNGrab needs 2 command lines (stash, then pull).")
        case "GrabBuffs":
            if (cmds.Length < 1)
                throw Error("GrabBuffs needs at least 1 command line.")
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
    bindings.Push({ enabled: true, hotkey: "F1", action: "PreSendChat", commands: ['.stp tpr '] })
    bindings.Push({ enabled: true, hotkey: "F2", action: "SendChat", commands: ['.stp tpa '] })
    bindings.Push({ enabled: true, hotkey: "F3", action: "StashNGrab", commands: ['.stash', '.pull "Blood Essence" 200'] })
    bindings.Push({ enabled: true, hotkey: "F4", action: "SendChat", commands: ['.stp tp shop'] })
    bindings.Push({ enabled: true, hotkey: "F5", action: "SendChat", commands: ['.stp tp home'] })

    bindings.Push({ enabled: true, hotkey: "F7", action: "GrabBuffs", commands: [
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