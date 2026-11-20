# Player Tags

**A World of Warcraft: Forever addon for remembering the people you meet.**

![The Player Tags list, with the tagging popup open beside it](screenshots/01-list-and-tag-popup.png)

You run a dungeon with a healer who carries the whole group, and a week later you can't remember their name. Or someone ninjas the last drop and drops group, and a month later they're in your party again and you don't recognise them until it's too late.

Player Tags fixes that. Tag a player in a couple of clicks (Helpful, Great Healer, Ninja Looter, whatever fits) and add a note if you like. The next time you cross paths, their tags show up in their tooltip, next to their name in chat, on their target and group frames, and on their Group Finder listing.

Everything stays on your computer. Nobody else can see your tags, and other players are never told you tagged them.

**[Download the latest version](https://github.com/itsMattGuenther/player-tags-wow-forever/releases/latest/download/PlayerTags.zip)** · [All releases](https://github.com/itsMattGuenther/player-tags-wow-forever/releases)

> **Beta.** Version 1.0.0-beta.2 is built for WoW: Forever (interface 16001) and has been played in game. If something looks wrong, type `/tags status` and [open an issue](https://github.com/itsMattGuenther/player-tags-wow-forever/issues) with what it says.

## What you get

**Tag anyone quickly.** Target a player and type `/tag`, press a key you bind, right-click a player or a name in chat, or right-click the minimap button. A popup opens with every tag, and you click the ones that fit.

**22 tags to start, in four families:**

| Good people | Skilled | Good to know | Avoid |
| --- | --- | --- | --- |
| Helpful | Great Tank | Hit & Run | Rude |
| Good Company | Great Healer | Quiet | Leaver |
| Generous | Big Damage | Crafter | Ninja Looter |
| Reliable | PvP God | Rival | Ganker |
| Patient | Good Leader | New Player | Scammer |
| | | Goes AFK | Griefer |

You can rename them, hide the ones you don't use, and make your own.

**See tags when it matters.**

- **Tooltips:** every tag, how long ago you added it, your note, and where you were when you tagged them.
- **Chat:** small tag icons in front of the sender's name.
- **Unit frames:** target, focus, party and raid frames.
- **Groups:** a short heads-up when someone you've tagged joins your group, plus an optional sound for Avoid tags.
- **Group Finder:** the leader's tags on a listing, and a count of other tagged players in the group.
- **Nameplates:** up to three icons by default (Avoid tags first), over enemy players in the open world.

**Your list.** `/tags` opens everyone you've tagged. You can search by name, tag or note, filter by family, and click a row to edit it.

![A tagged player's tooltip and target frame](screenshots/02-tooltip-and-target-frame.png)

*Hovering over a tagged player: their tags and your note in the tooltip, with tag icons above the target frame.*

## Private by design

- Your tags live in your own saved variables file on your computer.
- The addon contains no code that sends messages to other players. There's no shared blocklist, nothing to sync, and no account.
- There are no scores or ratings. A tag is a note to yourself, not a public review.

## Install

1. Download **[PlayerTags.zip](https://github.com/itsMattGuenther/player-tags-wow-forever/releases/latest/download/PlayerTags.zip)** from the latest release.
2. Find your WoW: Forever folder. In the Battle.net app, choose World of Warcraft: Forever, click the gear next to **Play**, and pick **Show in Explorer** (**Show in Finder** on a Mac). Open the `_forever_` folder.
3. Go into `Interface`, then `AddOns`. If either folder doesn't exist, create it.
4. Unzip `PlayerTags.zip` there. You should end up with `_forever_/Interface/AddOns/PlayerTags/PlayerTags.toc`.
5. Start the game, or restart it fully if it was already running. At character select, click **AddOns** and make sure **Player Tags** is ticked.

Use the zip from the Releases page, not GitHub's green **Code → Download ZIP** button. That one puts the addon a folder too deep, and the game won't find it.

**Updating:** delete the old `PlayerTags` folder in `AddOns` and unzip the new one in its place. Your tags are stored separately, so you keep them.

## Using it

| Do this | What happens |
| --- | --- |
| Target a player and type `/tag` | The tagging popup opens. Click tags to turn them on or off, type a note, press Esc. |
| Bind a key: Options → Keybindings → AddOns → Player Tags | The same popup with one key press. It works on your target, or on the player under your mouse. |
| Right-click a player, or a name in chat → **Tag player** | The same popup. |
| `/tag rude, leaver` | Adds tags to your target without opening a window. Handy in macros. |
| `/tag note <text>` | Sets the note on your target. |
| `/untag rude` | Removes one tag. `/untag` on its own removes them all. |
| `/tags` | Opens your list. |
| Minimap button | Left-click opens your list, right-click tags your target, drag to move it around the minimap. |
| `/tags options`, `/tags tags` | The options, and the tag editor. |
| `/tags export`, `/tags import` | Back up your list as text, or restore it. |
| `/tags status` | Shows what's loaded and any problems the addon caught. |

The list and the popup open in the middle of the screen the first time. Drag them anywhere and they'll open there from then on. If you'd rather the popup opened at your mouse pointer, there's an option for that.

Player Tags is also in the game's addon menu, the small numbered button by the minimap, even if you hide its own minimap button.

![The tag editor, with all 22 starter tags and the icons for custom tags](screenshots/03-tag-editor.png)

## Good to know

These limits come from the game, not the addon:

- **Nameplates inside dungeons and raids:** Blizzard locks friendly nameplates there, so group frames carry the tags instead.
- **Chat inside instances:** the game hides who's talking from addons, so chat icons don't appear there.
- **Friendly nameplates in the open world:** friendly players don't have nameplates by default, so nameplate icons appear over enemy players only. Friendly players' tags still show in tooltips, chat, and on target and group frames. An option, off by default, gives friendly players name-only nameplates so icons can sit above them too. Unticking it restores your previous settings.

**Backing up:** `/tags export` gives you your whole list as text you can save anywhere. `/tags import` brings it back. The data itself is in `_forever_/WTF/Account/<your account>/SavedVariables/PlayerTags.lua`.

<p>
  <img src="screenshots/04-options.png" alt="The options tab" width="49%">
  <img src="screenshots/05-minimap-button.png" alt="The minimap button and its tooltip" width="49%">
</p>

*Other players' names are hidden in these screenshots.*

## Feedback

Found a bug or have an idea for a tag? [Open an issue](https://github.com/itsMattGuenther/player-tags-wow-forever/issues). For bugs, include what `/tags status` says.

## For developers

```
PlayerTags/        the addon (this folder is what goes in Interface/AddOns)
  Core.lua         safe calls, events, module startup
  Tags.lua         families and the 22 starter tags
  Database.lua     saved data, player identity, tagging
  Icons.lua        icon atlas, inline icons, badges
  Widgets.lua      small self-drawn UI kit
  QuickTag.lua     the tagging popup
  Nameplates.lua   Tooltip.lua  Chat.lua  Menu.lua  Frames.lua  Group.lua  Finder.lua
  Share.lua        export / import
  Window.lua       the /tags window
  Minimap.lua      the minimap button
  Slash.lua        slash commands
  Media/           glyphs.tga (icon atlas), icon.tga, minimap.tga
tests/             offline checks that run the addon against a fake game client
tools/             build_icons.py (regenerates Media/), package.sh (builds the release zip)
screenshots/       images used in this README
```

- Run the checks with `lua5.1 tests/run.lua`.
- Regenerate the icons with `python3 tools/build_icons.py`. Add new glyphs at the end and never reorder them.
- Build the release zip with `tools/package.sh`. It writes `dist/PlayerTags.zip`.
- For local work, symlink `PlayerTags/` into `_forever_/Interface/AddOns`. `/reload` picks up code changes. New files or a changed `.toc` need a full restart of the game.
