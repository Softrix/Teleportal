
# Teleportal — About this addon

Teleportal is a small handy World of Warcraft addon for Mages to show both Teleports and Portals at the click of a button in a nice tidy frame.


# Commands & Macros

Teleportal is a **mage-only** addon. Slash commands and UI are only available on a character with the Mage class.

All commands work with either prefix:

- `/teleportal <command>`
- `/tp <command>`

Run `/teleportal` or `/tp` with no arguments to print a short help line in chat.

---

## Slash commands

| Command | Aliases | Description |
|---------|---------|-------------|
| **toggle** | `/teleportal toggle`, `/tp toggle` | Opens the teleport/portal spell panel if it is closed; closes it if it is open. |
| **hide** | `/teleportal hide`, `/tp hide` | Hides or shows the on-screen launcher button. State is saved between sessions - used for when launching from a macro. |
| **lock** | `/teleportal lock`, `/tp lock` | Locks or unlocks the launcher button so it cannot be dragged. State is saved between sessions. |

### toggle

Use this to open or close the two-column panel (teleports on the left, portals on the right) without clicking the launcher.

- The panel rebuilds from your spellbook each time it opens.
- Casting a teleport or portal from the panel closes it automatically.
- **Cannot open while in combat** (WoW secure-frame restrictions). Closing may be deferred until you leave combat.

### hide

Use this when you prefer to control Teleportal entirely from a macro and do not want the launcher visible.

- Hiding the launcher also closes the spell panel if it was open.
- The launcher frame still exists (hidden) and keeps its saved position; the panel anchors above that position when opened via `toggle`.

### lock

Use this after placing the launcher where you want it.

- While locked, the launcher cannot be dragged.
- Locking does not hide the button; use `hide` for that.

---

## Macros

### Open / close teleports and portals (recommended)

Create a macro with this line:

```
/teleportal toggle
```

Or the short form:

```
/tp toggle
```

Click the macro (or bind it to a key) to open the panel; click again to close it.

**Tip:** Put the macro on an action bar and bind a key in *Esc → Key Bindings* for quick access.

### Hide the launcher and use only the macro

1. Position the launcher where you want the panel to appear (the panel opens above it).
2. Optional: lock it in place:
   ```
   /teleportal lock
   ```
3. Hide the launcher:
   ```
   /teleportal hide
   ```
4. Use your toggle macro to open and close the spell panel.

To show the launcher again:

```
/teleportal hide
```

### Example: one-key setup macro (optional)

You can combine setup steps in a single macro only if you accept that `hide` and `lock` **toggle** each time you run it. For a one-time setup, run the commands manually once, or use separate macros.

**Daily use macro** (after setup):

```
#showtooltip Spell_Arcane_Teleport
/teleportal toggle
```

---

## Using the panel

When the panel is open:

- **Left column** — Teleport spells  
- **Right column** — Matching portal spells (blank slot if no portal exists for that destination)  
- **Classic** — Rune counts appear in the top row of each column  
- Click a spell icon to cast (subject to normal spell rules: range, reagents, cooldowns, combat where applicable)

---

## Notes

| Topic | Detail |
|-------|--------|
| **Class** | Addon loads UI only for mages. |
| **Combat** | Opening the panel via `toggle` (or the launcher click) is blocked in combat. |
| **Saved settings** | Launcher position, lock state, and hidden state are stored in `TeleportalDB`. |
| **Reload** | After installing or updating the addon, use `/reload` in-game. |

---

## Quick reference

```
/teleportal              Help in chat
/teleportal toggle       Open / close spell panel
/teleportal hide         Show / hide launcher button
/teleportal lock         Lock / unlock launcher position

/tp toggle               Same as /teleportal toggle
/tp hide                 Same as /teleportal hide
/tp lock                 Same as /teleportal lock
```
