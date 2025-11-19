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

1. Copy `ElegastCore` folder to `World of Warcraft/Interface/AddOns/`
2. Type `/reload` in-game
3. Type `/egc` for commands

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
