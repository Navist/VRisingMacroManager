# V Rising Macro Manager (Bloodcraft UI)

![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2-blue)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)
![Game](https://img.shields.io/badge/game-V%20Rising-red)

A **GUI-based macro manager built with AutoHotkey v2 for V Rising**,
designed to streamline chat commands and frequently used in-game actions
through customizable hotkeys.

The tool provides a clean, Bloodcraft-inspired interface that allows
players to **create, organize, and trigger macros without editing
scripts manually**.

---

# Overview

The **V Rising Macro Manager** allows players to bind macros to hotkeys
and execute in-game actions instantly.\
Instead of maintaining raw scripts, users can manage their macros
through an intuitive graphical interface with persistent configuration.

The application stores macro data in a configuration file and
automatically loads bindings when the program starts.

---

# Features

## Macro Management

- Create and assign macros to custom hotkeys
- Edit or remove existing macro bindings
- Persistent macro storage using a configuration file

## Macro Action Types

Supported macro behaviors include:

- **SendChat**\
  Sends a message directly to in-game chat.

- **PrefillChat**\
  Opens the chat box and pre-fills a command for manual confirmation.

_(Additional macro types may be added depending on the server or mod
environment.)_

## User Interface

- Bloodcraft-themed **dark UI**
- Optional **Light theme**
- Action help panel for contextual guidance
- Organized macro listing and editing

## Hotkey Safety

- Duplicate hotkey detection
- Visual feedback when conflicts occur

## Quality of Life

- Configuration automatically saved to an **INI file**
- System tray integration with quick access
- Tooltip and UI feedback for active actions

---

# UI Preview

---

Dark Mode Light Mode

---

`<img src="assets/darkMode.png" width="100%">`{=html} `<img src="assets/lightMode.png" width="100%">`{=html}

---

---

# Requirements

- **Windows**
- **AutoHotkey v2**

Download:

https://www.autohotkey.com/v2/

---

# Installation

Install **AutoHotkey v2**

Clone or download the repository

```bash
git clone https://github.com/Navist/VRisingMacroManager.git
```

Run the script

```bash
V_Rising_Macro_Manager.ahk
```

---

# Configuration

Macro bindings and settings are stored in:

    vrising_macros.ini

The file is created automatically when the program runs for the first
time.

---

# Intended Use

This tool is designed to simplify repetitive chat commands and
quality-of-life actions while playing **V Rising**, particularly on
servers that utilize custom commands or modded functionality.

It does **not automate gameplay mechanics** or interact directly with
game memory.

---

# License

This project is provided as-is for community use.
