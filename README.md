# ElegastCore

**Modular addon for ElegastCore server features**

Unified, extensible addon for custom WotLK server enhancements. One addon for all server-specific features.

---

## Features

✨ **Modular Architecture** - Easy to extend

🎮 **Draggable & Scalable UI** - Customize position and size of all displays

🔧 **Configurable** - Enable/disable modules individually

🎨 **Smooth Animations** - Professional polish

📦 **All-in-One** - Single addon install

👁️ **Minimal Mode** - Toggle compact text-only displays (right-click or command)


---

## Installation

1. Copy the `ElegastCore` folder to `World of Warcraft/Interface/AddOns/`
2. Copy the server's `patch-D.MPQ` to `World of Warcraft/Data/`
3. Delete `World of Warcraft/Cache/`
4. Launch, then type `/egc` for commands

That is everything — **two pieces**.

> ### ⚠️ Upgrading from an earlier install
>
> **Delete `Interface/AddOns/AIO`.** AIO is now bundled inside this addon. Leaving the
> old standalone copy enabled loads AIO twice, which can break the classless interface
> in ways that look like a server bug. The addon warns you in chat on login if it
> detects one.

### What is bundled

[AIO](https://github.com/Rochet2/AIO) by Rochet2 (GPL v2) lives in `libs/AIO/`. It is the
server-to-client transport the classless system uses — the server pushes its UI code
through it at runtime — so it is required, not optional. AIO's own dependencies,
smallfolk and lualzw (both MIT), keep their licenses in place.

This addon is therefore distributed under the **GPL v2**, matching AIO and the
[server repository](https://github.com/elegast-me/ElegastCore-Classless).

---

## Commands

**Main:**
- `/egc` - Show help
- `/egc modules` - List modules
- `/egc <module>` - Module help

**Module Commands:**
- `/egc <module> unlock` - Enable moving & scaling (shows griptape handle)
- `/egc <module> lock` - Save position & scale
- `/egc <module> reset` - Reset to defaults
- `/egc <module> minimal [on/off]` - Toggle minimal mode (text-only display)

**Quick Actions:**
- **Moving UI:** Shift+Drag or unlock mode
- **Scaling UI:** Drag corner griptape (unlock mode only)
- **Minimal Mode:** Right-click frame to toggle

---

## Modules

### InfinitePower
XP stack tracker with kill/quest progress. Shows stacks, percentage bonus, and progression stats. Auto-applies stat bonuses.
- **Normal:** Icon with stack count and XP bonus
- **Minimal:** Compact "102 | +204%" text

### ThreatenedAzeroth
Status indicator for Threatened Azeroth system. Shows active/inactive state, bonus rewards info.
- **Normal:** Icon with "TA" and status text
- **Minimal:** Compact "TA | Active/Inactive" text

### SpeedBuff
Speed buff stack display (1-4 stacks = 20-80% speed). Smooth animations, dynamic timer that shows countdown when movement stops.
- **Normal:** Sprint icon with stack count and speed percentage
- **Minimal:** Compact "4 | +80%" text

---

## Troubleshooting

**Not loading?** Ensure folder is named `ElegastCore`, then `/reload`
**Module disabled?** `/egc enable <module>`
**Can't move?** Use `/egc <module> unlock` or Shift+Drag

---

**WoW 3.3.5 (WotLK) | AzerothCore | GNU AGPL v3**
