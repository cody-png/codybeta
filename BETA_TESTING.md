# KIF Beta – testing this build

## Install (fresh)
1. Unzip the release into a **new, empty folder**. Don't unzip over an old KIF or PIF folder.
2. Get the sprite pack (`Full Sprite pack ... .zip`) and drop the **zip itself** into the `Import Sprites` folder next to `Game.exe`. Don't unzip it. **The zip is deleted once its sprites are installed** - keep your own copy elsewhere, or set Options > Others > Imported Archives to Keep first (it then goes to an `Imported archives` folder).
3. Start `Game.exe`. The first start sorts the pack into place (a few minutes for the full pack) and tells you how many sprites it imported. The zip is deleted once it's unpacked – the installed sprites are the only copy.
4. If you had saves in old KIF, the game offers once to copy them over. Say yes or no; you can copy them yourself later from the `Old Savefile location` shortcut.

Saves live in `%APPDATA%\KIF` (the `KIF Savefiles` shortcut). Old KIF's saves are untouched in `%APPDATA%\kurayinfinitefusion`.

## Reporting a bug
Send, in this order of usefulness:
1. **`KIF_log.txt`** from the save folder (`KIF Savefiles` shortcut). One file per play session; `KIF_log_previous.txt` is the session before. It says what the game could see (sprites, settings), what KIF did, any "?" sprites, and any crash with the last maps you were on.
2. A screenshot or short video.
3. Your save file, if the bug is tied to it (`File X.rxdata` from the save folder).
4. If the game crashed: `KIF_errorlog.txt` (next to `Game.exe`) or `errorlog.txt` (save folder).

## Things worth knowing
- **Pokédex "?" sprites:** PIF 6.8.2 reads base sprites from sprite sheets it downloads (15 per 2 minutes with *Download data* on). This build ships the base sheets and reads single sprite files first, so with the pack imported everything should show. If something still shows "?", the log lists it.
- **Entrance Randomizer:** if a shuffle ever leaves you somewhere you can't get out of, use **Return to Pokémon Center** in the pause menu. Each use is noted in `KIF_entrance_returns.txt` in the save folder – send that file too, it shows exactly where you were stuck.
- **Debug mode (this branch only):** `F7` on the map opens a testing menu: warp anywhere, give items/badges, party tools, Entrances helpers, cheats. Press `F9` for PIF's own debug menu.
