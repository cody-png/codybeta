# KIF changelog

Every KIF version, newest first: a short overview, then the full notes (click Full notes to open them).
The game shows the same notes in Options > System > Update history.

[1.2.9](#kif-129) | [1.2.8](#kif-128) | [1.2.7](#kif-127) | [1.2.6](#kif-126) | [1.2.5](#kif-125) | [1.2.4](#kif-124) | [1.2.3](#kif-123) | [1.2.2](#kif-122) | [1.2.1](#kif-121) | [1.2.0](#kif-120) | [1.1.1](#kif-111) | [1.1.0](#kif-110) | [1.0.7](#kif-107) | [1.0.6](#kif-106) | [1.0.5](#kif-105) | [1.0.4](#kif-104) | [1.0.3](#kif-103) | [1.0.2](#kif-102) | [1.0.1](#kif-101) | [1.0.0](#kif-100)

## KIF 1.2.9

- Fixed: on some PCs the screen stayed black for minutes after Play. The check for saves to import from old KIF now runs only when that folder changes, and never for more than 3 seconds.

<details><summary>Full notes</summary>

- Each time the load screen opened, KIF compared every save in the old KIF save folder (kurayinfinitefusion) with your saves, to know whether to show Import Old Saves. On a player's PC that took 158 seconds on every start. The answer is now remembered until the old folder changes, the check stops after 3 seconds (then Import Old Saves shows, and the import still skips saves you already have), and a check over a second is written to the log.

</details>

## KIF 1.2.8

- Faster start with a full sprite pack and Download data Off: the check before the load screen no longer goes through every sprite file.
- The log now says which step was slow when the load screen takes a while to appear (send the Logs folder if the screen stays black after Play).
- Verbose logging also turns on with a file named verbose or verbose.txt.txt in the Logs folder.

<details><summary>Full notes</summary>

- With Download data Off, PIF listed every file of the sprite pack (over 236,000 with the full pack) each time the load screen opened, only to check that there are at least 1000 sprites. KIF now reads the sprite list until it has counted 1000, which gives the same answer.
- When the time from Play to the load screen is over 3 seconds, the log says how long it took, and names every step that took over a second (closing the title, reading each save, the old save folder check, the sprite count, the sprite download check, drawing the save panels...).
- With verbose logging on, every one of those steps and the total are logged, however short.
- Verbose logging (for bug reports) turns on with verbose.txt, verbose or verbose.txt.txt in the Logs or save folder.

</details>

## KIF 1.2.7

- What's new opens a full-screen reader: Up/Down scroll, Left/Right turn pages, A or B closes.
- Options > Mods: press USE on a mod (Installed or Browse) to read its full description.
- New, Off by default: Items to Bag (Options > Pokemon > Catching). A Pokemon holding an item still steals with Thief/Covet and still finds items with Pickup in wild battles; the new item goes to the Bag.
- New, Off by default: Pre-Status (Options > Battles > Mechanics). Kuray Actions > Start Battles can make a Pokemon start every battle burned or poisoned.
- New, Off by default: Weather Setter Immunity (Options > Battles > Mechanics). Sand Stream and Snow Warning Pokemon take no damage from their own weather, whatever their types.
- Summary > Pokedex > Sprites also lists the sprites of the Pokemon's evolution line (Random Sprites On).
- The Custom starter menu has a third choice: Triple fusion.
- Hints name the controller button when you last pressed one.
- Old save import counts only saves and says when the File slots are full.
- Skip intro also skips the opening movie on a first start.
- No more "You have no more Pokemon that can fight!" after a forfeit.

<details><summary>Full notes</summary>

- What's new (before and after an update) opens the Update history's full-screen reader with every new version's notes: Up/Down scroll a line, Left/Right a page, A or B closes. No more three-line message boxes over a black screen.
- Options > Mods: press USE on a mod, in Installed or Browse, to read its README in the same reader. A mod that isn't installed is read from the catalog (and cached). Markdown shows as plain text; symbols the game's fonts lack become plain letters or are left out. A mod with no README shows its short description; offline says so.
- Items to Bag (Options > Pokemon > Catching, Off by default): in wild battles a Pokemon holding an item still steals with Thief or Covet, and still finds items with Pickup after battle; the new item goes to the Bag with a message. Only the wild Pokemon's own item is stolen: an item you gave it with Trick, Switcheroo or Bestow comes back after battle. Trainer battles, partners' Pokemon and Self-Battle work as before.
- Pre-Status (Options > Battles > Mechanics, Off by default): Kuray Actions (PC or party) > Start Battles: Normal, Burned or Poisoned. The Pokemon gets that status each time it is sent out without one, if it could get it at all (the same checks as Flame Orb and Toxic Orb).
- Weather Setter Immunity (Options > Battles > Mechanics, Off by default): a Pokemon with Sand Stream takes no sandstorm damage, and one with Snow Warning no hail damage, whatever its types. Works for both sides.
- Evolution line sprites: Summary > Pokedex > Sprites also lists the sprites of the Pokemon's evolution line (for a fusion, every head and body pair of its two lines). A pick there is for that Pokemon only. Random Sprites must be On. Blocking sprites lists only the species' own sprites.
- The Custom starter menu has a third choice, Triple fusion, with the 26 triple fusions. Fixed: triple fusion species numbers were read as two-part fusions and crashed when given by number.
- Hints name the controller button (A, B...) when you last pressed a controller button, and the keyboard key otherwise.
- Old save import counts only save files and says when the copies fill all 8 File slots.
- Skip intro also skips the opening movie on a first start, before any module is chosen.
- EBDX: the stat stage pills of a battle box with another box under it sit above its own name.
- After a forfeit, no more "You have no more Pokemon that can fight!" (a PIF bug).
- Options > System > Test Code's description is a full sentence.

</details>

## KIF 1.2.6

- New: Update history (Options > System). Read the notes of every KIF version: a short overview or the full notes.
- What's new shows the notes of every version since the one you had, so a skipped version's notes are no longer missed. After an update, All updates opens the Update history.
- Bag: a TM's menu has 'Who can learn' (every Pokemon that can learn its move) and 'Search TMs' (every TM, by move name).
- Illusion: a disguised foe's battle box shows the types of the Pokemon it copies until the disguise breaks.
- Battle Info's Log page shows your name where a line names you, and no longer shows text codes.
- Silph Co. 7F: a hidden tile in the west wall could undo beating Giovanni in Silph Co.; it's gone, and saves it affected are repaired on load.

<details><summary>Full notes</summary>

- Update history (Options > System > Update history): every KIF version, newest first. Pick one to read its Overview (the short notes) or its Full notes (every change you can notice). Up/Down scrolls a line, Left/Right a page. The mouse wheel scrolls too, a click or tap on the upper or lower half of the text turns a page, and one on the title closes it.
- The same notes are on the GitHub page, in CHANGELOG.md.
- After an update, "KIF was updated" offers OK, What's new and All updates (the Update history).
- What's new, before and after an update, shows the notes of every version newer than the one you have (or had before the update), so a version you skipped is no longer left out.
- Bag: a TM's or HM's menu has 'Who can learn': every Pokemon that can learn its move, the ones in your party and PC first, with a top row that switches between All, Seen and Caught. 'Search TMs' in the same menu lists every TM and HM by move name, also ones you don't have. The list also says that TMs are not used up and that a fusion learns a move if its head or body can.
- Illusion: while a foe is disguised, its battle box shows the types of the Pokemon it copies (PIF's type icons, KIF's Type Display and EBDX's box), as Battle Info and the Fight menu's hints already did. The real types show once the disguise breaks.
- Battle Info Log: a line that names the player shows your name, a line break in a message becomes a space, and the text codes in PIF's own messages no longer show as letters in the log.
- Test Code: a code that works but can't be kept (KIF can't write to its save folder) now says so, instead of saying Updates is set to Test.
- Silph Co. 7F: a hidden tile in the west wall could undo beating Giovanni in Silph Co.; it's gone, and saves it affected are repaired on load.

</details>

## KIF 1.2.5

- EBDX: move effectiveness shows in the Fight menu; battle boxes appear as each Pokemon is sent out, so the foe's lead stays hidden; foe type icons, KIF's shiny star, gender icons and level-up stat windows now show there too.
- Battle Info has a Log page: every message and ability pop-up of the battle so far, by turn (green dot: about your Pokemon, red: about the foe's).
- From the next update on, the game closes and restarts by itself a few seconds after the download (this one may still take about 20 seconds).
- Self-Battle's Stat Tracker line shows again in PIF's battle screen.
- Swap BattleGUI and Dark Mode's battle menus say they have no effect with EBDX Battles.
- In PIF's battle screen, the lower Pokemon's status tag in doubles is no longer cut off by the menu.

<details><summary>Full notes</summary>

**Battle Info**

- New Log page: every message and ability pop-up of the battle so far, grouped by turn, newest at the bottom. Up/Down scrolls. A green dot marks lines about your Pokemon and a red dot lines about the foe's (by the Pokemon each line names).
- The log works in PIF's battle screen and in EBDX, keeps Turn Skipper's sped-up or hidden end-of-round messages, and is kept for that battle only (never saved).

**EBDX battles**

- The Fight menu shows move effectiveness: each move gets KIF's marker at the end of its name (green up arrow, orange down arrow, grey X), and the hint above the selected move says Super eff., Resisted or No effect, or one line per foe in doubles and triples. Reported by PirateLady.
- The hint for a move in the lower row sits above its column's top button, and the hint lines sit on a dark strip, so they stay readable over your lower battle box in doubles.
- Battle boxes appear as each Pokemon is sent out, as in PIF's battle screen. Before, every box showed during "You are challenged by...", which gave away the foe's lead. A wild Pokemon's box still shows at the start.
- Battle boxes show the foe's types: PIF's small type icons with Type icons On and Type Display Off, the types it has in battle (after Soak, Transform and the like), side by side so they no longer cover the status tag.
- Battle boxes show KIF's coloured shiny star left of the name (two for a fusion that is shiny in head and body), KIF's gender colours, the genderless icon and the pizza icon.
- Level-ups show PIF's two stat windows after the jingle, so Auto-Battle's Level Up setting applies again. Base Stats Mode hides levels unless Show Lv. in BSM is On.
- Shiny Animation All sparkles every Pokemon at a wild battle's start and on each send-out.
- The battle box shows the real Pokemon as soon as an Illusion breaks.
- The Self-Battle stat tracker line shows on the top edge of the message box.
- Swap BattleGUI and Dark Mode's battle menus say they have no effect with EBDX Battles.

**PIF's battle screen**

- The Self-Battle stat tracker line shows again.
- The lower player box's status tag in doubles, partner and triple battles is drawn over the menu's edge instead of being cut off.

**Updates**

- After "The game closes now" the game closes by itself in about a second. Before, the message waited for a button and the update window closed the game after 20 seconds. The update window starts right after that message.
- Under Wine and Proton, "The game restarts now" goes on by itself too.

</details>

## KIF 1.2.4

- Battle Info: on the Abilities and Moves pages, press C (or Enter) on a row to read its full description (for a move: type, category, power, accuracy and PP too).
- Illusion: a disguised foe shows as the Pokemon it copies in Battle Info and the Fight menu's hints, and switches to the real one when the disguise breaks.
- EBDX: both teams' Poke Ball lineups show again at the start of trainer battles and when a Pokemon switches in, with the right balls in partner and two-trainer battles.
- Archipelago (apworld 0.7.0): new Dexsanity option. Each caught Pokemon is a check (a fusion counts both of its parts), with optional milestone checks.
- Options > System > Test Code: for invited testers only; everyone else can ignore it.
- Restarting the scripts with F12 (JoiPlay, Linux, macOS) no longer crashes with "stack level too deep".

<details><summary>Full notes</summary>

**Battle Info**

- On the Abilities and Moves pages, Use on a row opens its full description. For a move it also shows its type, category, power, accuracy and PP. Rows shown as ??? stay closed.
- Illusion: a foe disguised by Illusion shows as the Pokemon it copies (its types, ability, moves and a mod's innates) in Battle Info, its description boxes and the Fight menu's hints, instead of ??? rows that gave the disguise away. Foe Info: As seen shows what the battle has shown of that Pokemon. Everything switches to the real Pokemon when the disguise breaks.

**EBDX battles**

- Both teams' party lineups (Poke Balls for healthy, statused, fainted and empty slots) show again at the start of a trainer battle, and the switching side's lineup shows on a switch. Each hides at its send-out, as in PIF's battle screen. Reported by PirateLady.
- A partner's team no longer fills your lineup, and two foe trainers get 3 balls each. Your lineup sits between the foe trainer and your battle box in single battles.

**Archipelago**

- Dexsanity (apworld 0.7.0): registering a Pokemon as caught sends its Pokedex check (a fusion sends its head and its body). Optional milestone checks count the species you registered. Linking and loading send what the Pokedex already holds.
- A Dexsanity game refuses saves with random wild Pokemon or the other game mode (Classic or Remix), before anything in the save is changed. A linked save is warned once per load when it plays the other mode or has Nuzlocke on.
- The rebuilt apworld uses up evolution stones (one per species, Celadon's stones from the store), makes level evolutions wait for KIF's Hard level cap, and no longer counts Secret Garden Pokemon.

**Test builds**

- Options > System > Test Code is for invited testers. A pasted test code is checked and sets Updates to Test, which offers test builds (numbered like 1.2.3-test.1). Leave Test builds goes back to Beta. A cancelled or expired code says so and offers Beta.
- The code is kept only in the save folder, sent only to the test server, and shown masked in the log and on screen. A phone or a game folder KIF can't update is told test builds can't be installed there.

**Fixes**

- Restarting the scripts with F12 (JoiPlay, Linux, macOS) no longer crashes with "stack level too deep", also with Destiny Bond.

</details>

## KIF 1.2.3

- Battle Info: a foe's abilities and all its moves show from the start of the battle. Options > Battles > Screens > Foe Info: As seen keeps the old way.
- Archipelago (apworld 0.6.3): spots where only one of a group can ever give an item are one check, so every seed can be finished. Received items no longer freeze the game, and a DeathLink from another seed no longer wipes your team.
- Archipelago traps: items and traps wait until a battle's intro is over; Warp waits during scenes and resets a gym's type; Party Lock and Battle Trap fixes.
- EV Allocation: the 510 limit holds with vitamins and Wings, and moving HP EVs can't faint or revive a Pokemon.
- Mouse and touch: clicks cross into the next map and work with the Journey Camera mod; clicks in the EBDX fight menu and the Summary tabs pick the right thing.
- Randomizer: Route mode works with a read-only game folder (phones), and Return home is blocked on Pinkan Island. Nuzlocke: a Blackout no longer touches PIF's shared Transfer Box.
- Mods: emoji in mod.json, folders with [ ] in their name, and mod zips and catalog installs with a read-only game folder all work.
- Updates remove old editor and script files (.idea and the like) that older downloads left in the game folder.

<details><summary>Full notes</summary>

**Battle Info**

- A foe's abilities (KIF: Elite Redux innates too) and all its moves show from the start of the battle. New setting Options > Battles > Screens > Foe Info: All (default) or As seen, which keeps them hidden until the battle shows them.
- With Foe Info All, the Fight menu's effectiveness hints count a foe's ability from the start, as Battle Info lists it. A foe disguised by Illusion shows only what As seen would.

**EV Allocation**

- Spending stops at 510 EVs in all, also when vitamins or Wings were used while points were waiting. A Pokemon already past 510 EVs (from 1.2.0 to 1.2.2) no longer crashes battles, a knockout with Battles & Challenges Off, or a vitamin or Wing.
- Taking HP EVs that would make a hurt Pokemon faint is refused with a message, and giving HP EVs back no longer revives a fainted one.
- The points line after a win or a catch also shows with the pbGainMoney Base mod. "Use: spend them" no longer shows in battle or with Battles & Challenges Off, and Use on the contest condition page opens the item menu.

**Mouse and touch**

- A click or tap past the edge onto a connected map (a route next to a town) walks over to it.
- Clicks and the walk marker follow the Journey Camera mod's zoom and perspective.
- Holding the button no longer starts walking again after a text or menu closes. A held click keeps following the pointer through a ledge jump or a slide, and letting go (also during a message) ends it.
- A walk to a person that ends next to them early (on ice) talks to them instead of stopping.
- With KIF: Elite Redux, a click on a Summary tab opens that tab's page (Abilities too) and the keys follow it. A tab click on the contest page clears the condition bars.
- EBDX fight menu: a click off the moves uses no move, and a click on the Mega button toggles Mega.
- PC: a second click on the end of a box name switches box again instead of opening the box menu.
- Load screen: with no save, a click on the language globe no longer loads an empty save.
- Options > Mods: a click on an installed mod's Off/On switches it (a click on its name still opens Uninstall).
- Device: Mobile on a PC no longer turns pointer moves into clicks, and turning Touch controls Off and On again no longer taps where the finger last was.

**Living title screen**

- A follower sprite sheet that can't be read is never used for the title's fusions, so it can't crash the title.
- The title's Mods entry opens Modules when Mod Settings is Off or Hidden, and the Mods page then says to set Modules > Mod Settings to On.

**Randomizer and Nuzlocke**

- Return home and Return to Pokemon Center are no longer offered on Pinkan Island, where they sent you to the mainland with the quest team and an empty Bag.
- Wild Route mode with a read-only game folder (phones) no longer crashes Randomize now or a new game's intro, and Route Pokemon stay the same from one session to the next with randomized base stats.
- Nuzlocke: a Blackout no longer takes a Pokemon from PIF's shared Transfer Box (with none in this save's own PC the run ends), the Dupes clause ignores that box, and a dead Pokemon is no longer left out of the Graveyard after a reload.

**Archipelago (apworld 0.6.3)**

- Spots where only one of a group can ever give an item are one check (Pewter's benches, the Fighting Dojo's Pokemon, Route 24's Nugget, Violet's Slowpoke Tails), so every seed can be finished. Boon Island's sailor gets filler only.
- Received items no longer freeze the game for seconds when an item name has an accent.
- A DeathLink from another seed's game no longer wipes this save's team.
- Fishing, unfusing or a Bag item no longer sends the check of the last person you talked to.
- Items and traps wait until a wild battle's intro and fade-out are over.
- Battle Trap: the wild Pokemon stays one of the map's own when static encounters are randomized. Party Lock: a Self-Battle against a locked Pokemon from the PC no longer crashes. Warp Trap: waits while a scene holds you in place (Moonlit Forest's dream), and warping out of a gym resets its type, so trainers elsewhere keep their own teams.
- KIF Client: finds the game in folders with [ ] in the name, links right away after /game_folder, accepts a quoted path or a trailing space, and no longer writes an empty slot.json after a disconnect.

**Mods**

- A mod.json with emoji written as escape codes reads right, so Publish a mod can save it.
- Mod folders named with [ ] or { } get their pictures and sounds, and such a folder with only scripts is listed.
- With a read-only game folder, a mod .zip in the game's Mods folder is unpacked into the save folder's Mods and loads (an uninstall sticks), and a catalog install on a computer goes into the save folder's Mods instead of failing.
- Mod installs skip authors' git and editor files inside a mod folder, but keep a mod's own files.

**Sprite import (read-only game folder, phones)**

- Loose sprites are imported once instead of read again at every start, and the "Keep the ones I have" list is read once per start.
- An import cut off mid-sprite writes that sprite again at the next start instead of asking to keep the broken one.
- A zip of only sprite sheets, triple fusions or eggs is no longer reported as "couldn't be unpacked" at every start.

**Other**

- F12 on phones, Linux and macOS keeps the fix for JoiPlay's title-screen crash.
- Updates remove editor and script files older downloads left in the game folder (.idea and the like). The game no longer ships the tester guide, build scripts or PIF's leftover files.
- Options > System > Updates describes Beta as the newest version.

</details>

## KIF 1.2.2

- Prices: every price in shops, hotels, gates, tutors and gifts now reads like the Poke Mart's ($1,000).
- Entrance Randomizer: Pokemon whose level is scaled now know the moves of their new level.
- Mods: mod settings stay visible after F12 on phones, Linux and macOS.

<details><summary>Full notes</summary>

- Prices: every price in every PIF event and common event reads like the Poke Mart's ($1,000, $50, $200,000): hotels, hair dye, the lottery, gamblers, tutors, rewards and gates. Prices that come from the game (tutors, gamblers' bets, debts) too. The money charged is unchanged.
- Translated (French) lines keep their own text, also after switching language.
- Entrance Randomizer: a Pokemon whose level is scaled gets the moves of its new level, picked the way PIF picks them.
- Mods: mod settings stay visible after F12 on phones, Linux and macOS.

</details>

## KIF 1.2.1

- Fixes: the Bug-Catching Contest no longer crashes when the Randomizer module is Off.
- Modules: Battles & Challenges Off now also turns off KIF's critical captures and Challenge Modifiers, and Pokemon & Fusion Off turns off Head Legendary Breeding.
- Updates: the updater gives up after many failed downloads in a row, warns about unsaved progress when you update from inside the game, and finishes under Wine or Proton (Steam Deck) even when a file is in use.
- Saves: an unreadable save no longer crashes the save menu, and when no save can be read the load screen opens its newest backup. Saving writes a temporary file first, so a failed save keeps the old one.
- Mods: catalog updates go to the copy of a mod that actually loads, and a mod you update by hand in the save folder's Mods folder wins over the game's older copy.
- Gate, reward and Celadon Cafe prices read like the Poke Mart's ($200,000).
- New Game+: Pokemon of unknown species are set aside instead of turning into Pichu.
- Save menu and load screen messages use the normal text box.

<details><summary>Full notes</summary>

**Modules**

- Battles & Challenges Off turns off KIF's critical captures and the Challenge Modifiers' forced moves too.
- Pokemon & Fusion Off turns off Head Legendary Breeding, and Auto Battle Off turns off Auto-Battle's switching too.
- Randomizer Off no longer crashes the Bug-Catching Contest.

**Saves**

- The main save is written to a temporary file first, so a failed save keeps the old one.
- An unreadable save file shows as "can't be read" in the save menu instead of crashing it. With no readable save, the load screen picks one that has backups, so its newest backup loads and Savefile management reaches the older ones.
- Save menu and load screen messages use the normal text box (its place and its text colour), also after an event such as the new-game intro used another one.
- Save previews on the load screen no longer set aside or give back Pokemon and items; the real load does it once.
- Set-aside items: a berry given back while loading no longer causes an error, and an item leaves the set-aside list as soon as it is in the Bag.
- New Game+: Pokemon of unknown species are set aside instead of turning into Pichu, and the old save's set-aside Pokemon and items come along.

**Updates**

- One-at-a-time downloads stop after 20 failures in a row.
- Updating from inside the game warns about unsaved progress on every platform.
- Under Wine or Proton (Steam Deck), a file the game has open is moved aside so the update finishes.
- An older version's unfinished update folder is removed.

**Mods**

- With a read-only game folder, a mod you update by hand in the save folder's Mods loads instead of the game's older copy, in the same place in the load order.
- Catalog updates go to the copy of a mod that actually loads, not a backup or a switched-Off copy.
- Options stays behind the mod catalog's questions (Install, Update, Modpacks, Share Code, Uninstall) instead of the map.

**Other**

- Prices: the Celadon Cafe's Pokemon seller reads $15,000 everywhere, and gate, reward, Game Corner and Saffron gate guard prices read like the Poke Mart's ($200,000). Translated lines stay as they are.
- Archipelago: the game ships kif.apworld 0.6.2 and KIF.yaml (every option at its default) in its Archipelago folder.

</details>

## KIF 1.2.0

- A much smaller game: about 920 MB instead of 1.68 GB (this update is about 680 MB). Pictures look the same; music and sounds are now Ogg.
- Faster start-up, and menus check the disk far less.
- New: Mouse and touch controls (Options > System > Controls, Off by default). Click or tap to choose, click or tap the map to walk there.
- New: EV Allocation (Options > Pokémon, Off by default). EVs from battles become points you spend on the Summary's Skills page.
- New: Living title screen (Options > System > Title screen).
- New: Archipelago (beta). Play KIF in a multiworld: Kanto, Sevii and Johto, Trainersanity, Giftsanity and 10 kinds of traps. Use apworld 0.6.2.
- Nuzlocke: options for gift Pokemon and the Safari Zone. Pinkan Island now plays as in PIF with the Randomizer, Nuzlocke and Archipelago.
- Saves: new backups are compressed, and Compress old backups (Save menu) shrinks older ones. Compressed backups only load in 1.2.0 and later.
- Mods: publish your own mod to the catalog (Options > Mods > Installed, PC).
- Phones: KIF updates itself on JoiPlay and Kirin from the next update on, and mods download from the catalog.
- Fixes: waterfalls, Chip Away / Sacred Sword / Darkest Lariat against evasion, Wonder Trade's banned list, the Celadon Cafe seller, Level caps on a new save, and a broken custom sprite file no longer crashes the game.

<details><summary>Full notes</summary>

**A smaller, faster game**

- The download is about 920 MB instead of 1.68 GB, and the installed game is about 830 MB smaller. This update is about 680 MB.
- Pictures were recompressed without changing a single pixel. Uncompressed and high-bitrate music and sounds are now Ogg files of the same length, so looping music still lines up. Four data files the game never read are gone.
- After installing over an older version, the old .wav and .mp3 copies of sounds are removed once, so the new files are the ones that play. A sound you put in yourself is kept.
- Start-up is about 2 seconds quicker: the game's text is read once and kept ready for the next start.
- Menus check the disk far less (opening the party went from over 500 checks to under 40), which helps most on phones.

**Mouse and touch controls**

- Mouse (Options > System > Controls, Off by default, PC only): point at an entry to select it, left click to confirm, right click to go back, wheel to scroll. A click also moves a message on. Works in choice boxes, Yes/No, the pause menu, the Bag, the party, the Summary tabs, PC boxes (the wheel flips boxes), battle menus, the load screen, the title menu, Options and EV Allocation.
- Click to move (On while Mouse is On): click a tile and you walk there, around walls, people and water, down ledges and over stairs and bridges. Click a person or object to walk up to it and talk. Hold the button to keep walking toward the pointer. Any key or a new click stops the walk.
- Touch controls (phones, Off by default): taps work like clicks, quick taps too. Tap to move works like Click to move. JoiPlay's and Kirin's on-screen buttons keep working.

**EV Allocation**

- Options > Pokémon > EV Allocation (Off by default): EVs won in battle wait on the Pokemon as points, and you spend them on the Summary's Skills page (keys, mouse or touch).
- The end of a battle says how many points each Pokemon got. The usual limits stay: 252 in one stat, 510 in all. You can put every point back and spend them again for free.

**Living title screen**

- Options > System > Title screen: Living, Simple or Classic (Living by default; Simple on phones).
- Pokemon wander through a slowly scrolling field, beach and forest behind the title menu (Play, Options, Mods, Links, Quit). Now and then two of them meet and fuse.

**Archipelago (beta)**

- Play KIF in an Archipelago multiworld with apworld 0.6.2 and the KIF Client. kif.apworld and KIF.yaml (every option at its default) are in the game's Archipelago folder. Link a save from the pause menu (Archipelago); other saves play as normal.
- Checks: Kanto's item balls, gifts and gym badges. Goal: the Hall of Fame, or the 8 gym leaders.
- Regions: Kanto (default), Kanto + Sevii Islands, Kanto + Johto, or all three: up to 761 checks and 15 badges. Pinkan Island is never part of it.
- Options: Trainersanity (up to all 219 Kanto trainers), Giftsanity (26 gift Pokemon and eggs), badges for the League, shuffled badges, DeathLink, game difficulty, field moves without badges, an exp modifier, a minimum catch rate or guaranteed catches, starting money, a free Fly town and start items.
- Traps (Off by default): Poison, Paralysis, Battle, Confusion (directions shuffled for 50 steps), Money, Fusion Swap, Party Lock (one Pokemon sits out for a while), Warp (back to your last Pokemon Center), PP Drain (one move of your lead runs out of PP) and Disobedience Curse (your Pokemon ignore some orders until your next Pokemon Center). Traps wait for a quiet moment on the map, and a Battle trap never starts a battle in a Nuzlocke run. The party screen marks LOCKED and CURSED Pokemon.
- Seeds can always be finished: the logic was checked against the real maps, and missable spots only hold filler.
- The slot's randomizer settings, seed and difficulty are applied when a save is linked. The pause menu's Archipelago entry shows whether the KIF Client is connected and how many checks were sent and received.
- A broken or half-written client file no longer crashes the game, and a loaded save sends its checks and goal again. DeathLink with Nuzlocke buries the team and never costs a PC Pokemon.

**Nuzlocke**

- Gift Pokemon: Free (default) or Counts. With Counts, a gift, egg or trade uses up the place you got it in, if you haven't had that place's encounter yet. Your starter and unfusing never use up a place.
- Kuray Shop: Counts (one K-Egg per run) or Free.
- Safari Zone: Per area (default) or Whole zone. Only a catch uses up the place there.
- The team that falls in the run's last battle goes to the Graveyard too. A finished run's save shows a small grave on the load screen.

**Pinkan Island**

- With the Randomizer, Nuzlocke and Archipelago, Pinkan Island plays as in PIF: its wild Pokemon, bosses, gifts, trainers, items, requests and move tutors stay as they are, and no Nuzlocke rule applies there.

**Saves**

- New backups are compressed (about a tenth of the space). Older ones still load.
- Compress old backups (in the Save menu) shrinks the backups made before. Each one is checked before its old copy is replaced. Compressed backups only load in KIF 1.2.0 and later.
- Loading an older save file no longer runs the newest file's events (such as another file's new-game intro).
- Items from a mod you turned off or removed are set aside when the save loads (Bag, PC items, held items) instead of showing as UNKNOWN, and come back when the mod does.

**Mods**

- Publish a mod (Options > Mods > Installed, PC only): fill in the mod's details and tags, run the catalog's checks in game, then send it to the catalog with your own GitHub account.
- A local catalog folder written the Windows way (with backslashes) or with [ ] or { } in its name now shows its mods.
- Mouse UI loads again.

**Phones (JoiPlay and Kirin)**

- KIF updates itself on phones whose game folder can be written (JoiPlay and Kirin): only the changed files download, and you close and reopen the game when it's done. This starts with the update after 1.2.0. A phone whose game folder can't be written is told about new versions instead.
- Mods download and install from the catalog.
- With a read-only game folder, caches, Randomizer files and update downloads go to the save folder, and Import Sprites and Mods are read from there too. Logs go to a folder you can open.
- Sprite packs import about twice as fast, and a game closed mid-import picks up where it stopped without touching your own sprites.
- Frame rate offers 40 and 60, key hints name the gamepad buttons, and a change of speed or Auto-Battler shows on screen.

**Installers and updates**

- The installers say KIF. A release's installer can install "this version only", which skips the automatic update check.
- An update window closed after the new files started moving in is finished at the next start. Downloads stop trying after many failures in a row when the server is down.

**Entrance Randomizer**

- Dive comes from HM06. The door data was rebuilt with a corrected world model, and a door nothing opens (the Hidden Tomb) leads into a place that gives nothing.
- A layout gets up to 400 tries, so seeds that gave up before now work.

**Fixes**

- Waterfalls work again (also in 1.1.1).
- Chip Away, Sacred Sword and Darkest Lariat ignore the target's evasion boosts.
- A broken custom sprite file (one that isn't a real picture) no longer crashes the game: it is skipped, the normal sprite shows, and its name is in Logs/KIF_log.txt.
- Wonder Trade never gives Arceus, Mew, Celebi, Lugia, Ho-Oh or Mewtwo (its never-give list didn't work).
- The Celadon Cafe Backstore's Pokemon seller restocks again instead of crashing.
- Level caps can be changed with the keys on a new save.
- A Linux PC whose game folder is under /data or /storage is no longer treated as a phone.
- The Living title's flying Pokemon are no longer cut off.

</details>

## KIF 1.1.1

- Waterfalls work again: face one and press the confirm key to climb it with the HM, the Jetpack or Quick HMs.

<details><summary>Full notes</summary>

- Waterfalls work again: face one and press the confirm key to climb it with the HM, the Jetpack or Quick HMs. PIF 6.8.2 had this turned off.

</details>

## KIF 1.1.0

- New: Nuzlocke (Options > Challenges). First encounter per place, Dupes and Shiny clauses, fainted Pokemon die. Fainted ones go to the Graveyard (pause menu, PC), are released or stay. A full wipe can keep playing, lock the save, or black out.
- Randomizer: banning every non-legendary no longer freezes Randomize. Remix and Expert trainers that use a Classic team are shuffled too.
- Overworld Encounters (mod): its Pokemon follow the Randomizer.
- Save Backups: new Off choice; Newest 10 is the default for new players.
- Faster start-up: PIF's Pokedex file is downloaded once a week, mod updates are checked twice a day at most.
- Crash fixes: the Johto/Hoenn/Sinnoh starter labs, trainers missing from the Classic list, Synchronize under Safeguard, Grass + Fire Pledge, doors to maps that don't exist, the Silph Co. elevator on a new game, the Registeel ice puzzle, the Water Labyrinth, Cinnabar Lab's fossil list.
- Security: a secret base, mystery gift code or sprite preferences file from another player can no longer run code on your PC.
- Mods: a garbled share code no longer closes Options; a mod update never deletes a file you edited.

<details><summary>Full notes</summary>

**Nuzlocke (Options > Challenges > Nuzlocke)**

- First encounter only: only the first wild Pokemon you meet in each place can be caught. All floors of a map count as one place.
- Dupes clause (On by default): a Pokemon whose evolution line you already have doesn't use up the place. Shiny clause (On by default): a shiny can always be caught.
- Fainted means dead: a dead Pokemon can't be healed, revived, levelled up, fused or unfused. When a fusion faints, both halves die. If a Poke Ball is refused, a short message says why.
- Fainted Pokemon: Graveyard (a box you can look at but never change, opened from the pause menu or the PC), Released, or Stay.
- When the whole party is dead: Keep playing (the run ends and Nuzlocke turns off), Lock save (the load screen marks the save with a grave and only shows its Graveyard; its autosaves and backups are locked too) or Blackout (you black out and a Pokemon from your PC joins you).
- Gift Pokemon never use up a place.

**Randomizer**

- Remix and Expert trainers that use their Classic team are shuffled too (about 40 crashed before), and an Endgame Challenge team met with the challenge off is shuffled instead of crashing.
- Banning every non-legendary Pokemon no longer freezes Randomize.
- Pokemon picked from a map's table (the Overworld Encounters mod, the Bug-Catching Contest) follow the Swap and Dynamic modes. The Bug-Catching Contest no longer crashes when it picks a Pokemon.

**Faster and lighter**

- PIF's 23 MB Pokedex entries file is downloaded once a week instead of at every start (antivirus programs that scan downloads made it crawl). PIF's settings file is downloaded once a day.
- Mod update checks run at most every 12 hours, are skipped on a slow or blocked connection, and take one small request when nothing changed.
- KIF's own start-up work is much quicker. Phones get smaller picture caches, the first shiny of a session no longer freezes the game, and Frame rate stops retrying a rate the device can't keep up.
- Sprite pack unpacking picks up where it stopped after the game was closed, never leaves a broken sprite behind, and checks files faster.

**Crash fixes (PIF bugs)**

- Battles: Synchronize against Safeguard, Grass Pledge with Fire Pledge, and PIF's AI against a Pokemon with no type or with Spikes down.
- The Johto, Hoenn and Sinnoh starter labs crashed when Blue walked up.
- Trainers missing from the Classic list (the S.S. Anne rematch, New Bark Town's gambler) crashed before the battle.
- Seven doors and warps led to maps that don't exist (Train Station, Route 39, Mt. Moon, Boon Island, Ecruteak, Underwater, Silph Co. 6F); you now stay where you are.
- The Silph Co. elevator on a new game, the Registeel ice puzzle and the Water Labyrinth.
- Three developer test NPCs that crashed are gone (Pallet Town, Olivine City, Olivine Mart).

**Saves and settings**

- Save Backups: a new Off choice (no new backups; named backups still work), and PIF's choice is now called Newest 10. Newest 10 is the default for new players.
- Settings files that can't be read are kept as .bad files instead of being overwritten.

**Security**

- A secret base, mystery gift code or sprite preferences file from another player could run code on your PC. It can't anymore.

**Mods**

- A garbled share code is refused instead of closing Options.
- A mod update never deletes a file you edited.

**For bug reports**

- Logs/KIF_log.txt records the engine, screen and controller, mod versions, each save loaded and saved, how long the start-up downloads took, and the battle when a crash happened. An empty verbose.txt in the Logs folder gives a much more detailed log.

</details>

## KIF 1.0.7

- Randomizer: Built-in presets to start from (First Randomizer, Gym Challenge, Item Hunt, Fusion Frenzy, Dungeon Crawl, Total Chaos), in Presets & sharing.
- Entrances: Which doors has a Custom choice. Door kinds picks which kinds of door are shuffled (Centers, Gyms, Marts, Houses, other buildings, Gates, caves).
- Entrances: Door signs. Facing a shuffled door you have used shows where it leads, in the corner or above the door.

<details><summary>Full notes</summary>

- Randomizer: built-in presets to start from, in Presets & sharing: First Randomizer, Gym Challenge, Item Hunt, Fusion Frenzy, Dungeon Crawl and Total Chaos.
- Entrances: Which doors has a Custom choice, which opens a Door kinds page: Centers, Gyms, Marts and shops, Houses, other buildings, Gates, caves and dungeons.
- Entrances: Door signs. When you face a shuffled door you have used, a sign shows where it leads, in the corner or above the door.

</details>

## KIF 1.0.6

- The game now says KIF instead of KIF Beta (update messages, the welcome message, randomizer logs).
- KIF_log.txt now records more about downloads, the engine and the controller in use, to help with bug reports.
- A leftover testing file is removed from the game folder.

<details><summary>Full notes</summary>

- The game says KIF instead of KIF Beta in its text (update messages, the welcome message, randomizer logs).
- KIF_log.txt records which engine runs the game, how update downloads went and which controller is in use.
- Updates remove a leftover testing file (BETA_TESTING.md) from the game folder.

</details>

## KIF 1.0.5

- A list of choices next to a speech bubble stays on screen. The Cinnabar Lab fossil list could go off the top of the screen.

<details><summary>Full notes</summary>

- A list of choices next to a speech bubble stays on screen: when it doesn't fit above or below the message, it goes on the side with more room and scrolls. The Cinnabar Lab fossil list could go off the top of the screen.

</details>

## KIF 1.0.4

- PlayStation (including DualSense Edge), Switch and other non-Xbox controllers work: KIF is on the newer game engine again.
- Water, weather and other animations move on the newer engine, and new fusion icons show right away.

<details><summary>Full notes</summary>

- PlayStation (including DualSense Edge), Switch and other non-Xbox controllers work: KIF is on the newer game engine again.
- Water, weather, other timed animations and the Frame rate setting work on the newer engine, and new fusion icons show right away.

</details>

## KIF 1.0.3

- Water, weather and other animations move again, and new fusion icons show right away: KIF is back on the game engine of 1.0.0 and 1.0.1.
- The newer engine from 1.0.2 (for PlayStation and Switch controllers) is being tested and comes back in a later update. Until then, Steam Input or DS4Windows makes those controllers work.

<details><summary>Full notes</summary>

- On the newer engine of 1.0.2, water, weather and other timed animations stood still, and a fusion (or evolution) you made had no icon until the game was restarted. KIF is back on the game engine of 1.0.0 and 1.0.1, where both work.
- The newer engine (for PlayStation and Switch controllers) comes back in a later update. Until then, Steam Input or DS4Windows makes those controllers work.

</details>

## KIF 1.0.2

- Mods: installing a mod from Options > Mods > Browse works again. In 1.0.0 and 1.0.1 it failed on Windows and opened the old Options screen instead.
- Controllers: PlayStation, Switch and other controllers that aren't Xbox-style are recognized again (KIF now uses the same game engine version as old KIF).

<details><summary>Full notes</summary>

- Mods: installing a mod from Options > Mods > Browse works again. In 1.0.0 and 1.0.1 it failed on Windows and opened the old Options screen instead.
- Controllers: PlayStation, Switch and other controllers that aren't Xbox-style are recognized again. KIF now uses the same game engine version as old KIF.

</details>

## KIF 1.0.1

- Mods: the catalog of KIF's own mods is now called KIF Mods (cody-png) in Browse.
- Mods: Browse reads a new mod catalog correctly from the start (a brand-new catalog could look empty for a few minutes).
- The feature guide (KIF_Features.md) and the README are tidied up and use the KIF 1.0 name.

<details><summary>Full notes</summary>

- Mods: the catalog of KIF's own mods is called KIF Mods (cody-png) in Browse.
- Mods: Browse reads a brand-new mod catalog correctly from the start. It could look empty for a few minutes.
- The feature guide (KIF_Features.md) and the README use the KIF 1.0 name, list the credits and the Options section names, and have their typos and broken links fixed.

</details>

## KIF 1.0.0

- The first full release of KIF on Pokemon Infinite Fusion 6.8.2. Every KIF 0.20.7 feature is carried over, and KIF 0.20.7 saves load.
- Modules (Options > Modules): turn any part of KIF On, Hidden or Off. The first start asks: Classic KIF, PIF only or Let me choose.
- One Options screen for KIF's and PIF's settings, with search and Settings Presets.
- A new Randomizer screen with seeds and settings codes, and the Entrance Randomizer (beta), which shuffles where doors lead.
- New: Battle Info, the Fusion Screen, Move Effectiveness and EBDX battles (EBDX is Off by default).
- Mods: a built-in Mod Manager (Options > Mods) finds, installs, updates and removes mods.
- KIF updates itself and downloads only what changed. Sprite packs go in the Import Sprites folder.

<details><summary>Full notes</summary>

**Getting started**

- Install with install_KIF.bat (Windows) or install_KIF.sh (Linux, Steam Deck). The game is started with InfiniteFusion.exe.
- Coming from KIF 0.20.7: the first start offers to copy your old saves (old KIF keeps its own). Party, boxes, Bag, money, badges, position, KIF settings and shiny colours carry over. Pokemon whose species PIF 6.8.2 doesn't have are set aside, never emptying your party, and come back once the game has their species. Import Old Saves on the load menu does it any time; nothing is overwritten.
- KIF keeps its saves in %APPDATA%\KIF (the KIF Savefiles shortcut); old KIF's stay in %APPDATA%\kurayinfinitefusion.
- The first start asks how you want to play: Classic KIF (KIF as it was: every module On, but EBDX battles, Battle Info, Move Effectiveness and the Fusion Screen Off), PIF only (everything Off) or Let me choose.

**Modules and Options**

- Every feature belongs to one of 13 modules: Auto Battle, Shinies, Graphical Changes, Information, Battles & Challenges, Randomizer, Pokemon & Fusion, Kuray Shop, K-Eggs, PC & Saves, Import & Export, Quality of Life and Mod Settings. Each is On, Hidden (works, settings tucked away) or Off (plays like PIF).
- Items and menus PIF has its own version of (Ability Capsule, Mist Stone, Perfect Ball, the randomizer menu, breeding, naming screens) go back to PIF's when their module is Off.
- One Options screen replaces the separate settings pages and holds PIF's own options too. Sections on the left (Shinies, Battles, Pokémon, Graphics, Self-Battle, Challenges, Game, System, Modules, Mods, Presets), settings on the right under headings, each with a bar of choices and a description at the bottom.
- An orange dot marks a setting you changed, and it can be set back to its default. The bottom bar shows the default and whether the setting is for this save or all saves. A search bar lists every matching setting from every section.
- Settings Presets (Options > Presets): 12 named slots that hold every per-save KIF setting.
- Every screen names the keys you actually bound. DEBUG turns on PIF's real debug mode. The window title shows the KIF and PIF versions, the speed and the Auto-Battler or Battle Loop state.

**Randomizer**

- A new Randomizing screen replaces PIF's randomizer menu. It works from a new game, from the Update Man and mid-game on a randomized save. Changed settings wait for Randomize now; leaving with changes asks Randomize now, Keep for later or Undo. Your party and boxes stay.
- Seeds are 8 characters: the same seed and settings give the same game. Copy settings code puts the seed and every setting on one line to share. Presets go in the Randomizer/Presets folder.
- Wild Pokemon: Off, Swap, Route, Dynamic or Dynamic Route. The Poke Radar's lists match what appears. Starters, static encounters, gifts, trades and NPC requests each have their own switch, and the NPC names the new Pokemon.
- Trainers: Off, Random or Follow wild, with class themes (Bug Catchers use Bug types), team size, fusion odds and the rival keeping his team. Gyms get Leader team size, and the Kanto leaders say the real team counts.
- Items, TMs and shops: Mapped or Dynamic, found, given and shop items separately, trainer held items, categories kept if you like, and banned items.
- Pokemon data: types, abilities, base stats and evolutions, with moves and TMs that follow the new types. Exclusions: Pokemon, moves and abilities the randomizer never picks.
- A spoiler log you can read in game (Up/Down, Left/Right a page, a key to jump to a dex number or text).

**Entrance Randomizer (beta)**

- Randomizer > Entrances shuffles where doors lead: gyms, Centers, marts, houses, caves, towers, gates, tunnels, the Mansion, the League and Victory Road (170 Kanto doors). And Johto? adds 103 doors, And Sevii? adds 33.
- Settings: Entrances Off, Simple or Full; Which doors; Coupled doors; Door hints.
- Every layout is checked before it is used: it reaches everything the normal game reaches and can be finished from where you start, with the badges, HMs, key items and story events each place gives. Randomize now mid-run is checked from where you stand.
- Random start: skip Oak's errand and begin in a random town or map. Once you have your starter, the next door gives you the Pokedex and five Poke Balls and leads to your new home Center.
- Level scaling: trainers (and optionally wild Pokemon) are as strong as they would be at that point of the game.
- Entrance log: the Town Map and the Fly map draw a line for every door you've used, and the spoiler log lists the layout.
- Return to Pokemon Center in the pause menu takes you to your last Center (or home, if that Center is a dead end for now).

**Battles**

- Elite Battle DX (Options > Battles > EBDX, Off by default): animated battle scenes, camera movement and EBDX's battle boxes, with Camera Zoom, Stat Stage Icons and Own Trainer Animation. Thanks to Luka S.J. for EBDX and to Aleks for the KIF Multiplayer adaptation, included with permission.
- Battle Info: a key or the INFO tab above the battle menu opens pages for each Pokemon: stat changes, ability, held item and effects; abilities with descriptions (also those mods add); moves with type, category, power, accuracy and PP; who moves first this turn; and the field's effects, weather and hazards. A foe's abilities and moves show once the battle reveals them.
- Move Effectiveness: the Fight menu marks each move as super effective, resisted or no effect against the foe, with one line per foe in doubles.
- Battle AI: a choice of PIF or DemICE (0.20.7 always used DemICE). DemICE's AI is faster, three of its crashes are fixed, and both AIs make better damage guesses and better choices (trapping, status moves into absorbing abilities, Frostbite and Drowsy, Last Resort).
- Battle Format 1v1, 2v2 or 3v3, with Format Applies To: Wild, Trainers or Both.
- Gym Leader teams (+1, +2, Full) bring extra Pokemon of the gym's type, and Your Pokemon in gyms raises how many you may bring. Trainers keep their rolled abilities and shininess for every rematch.
- Auto-Battle is in Options only (no battle key) and no longer stops to ask: new settings for Switching, Level Up, New Moves and Evolutions.
- Level caps Easy, Normal and Hard work on top of PIF 6.8.2's cap table. Smart (default) saves Exp past the cap and gives it back when the cap rises; Lock stops Exp at the cap; RC turns extra levels into Rare Candies.
- Critical Captures is an option (default On). Forced Metronome and Splash respect sleep, freeze, paralysis, confusion, flinching, Taunt and disobedience. Modern Hail's Defense boost only applies against physical moves, and Frostbite no longer stops a Pokemon from moving.
- Type Display shows the types a Pokemon has in battle. Dark Mode gives battles KIF's dark message box and menus. Show Lv. in BSM keeps levels visible in Base Stats Mode. Sprites drawn as a strip of frames move in battle.
- The Endgame Challenge works as in 0.20.7, the Fighting Arena leaders no longer crash, and Dem's challenge unlocks again. Self-Battle's Battle Loop is an option, and Self-Battles no longer use up items from your Bag.

**Shinies**

- KIF's shiny colours run on PIF 6.8.2's sprite sheets; shinies from old saves look exactly as they did. PIF's Improved Shinies use PIF's newer palette code.
- New: Shiny Filter (cleans up colours that came out inverted or nearly the same as the normal sprite) and Shiny Cache (shinies draw faster).
- Fusing copies head and body colours with Shiny Fuse Dye, the DNA Reverser swaps them and unfusing gives the originals back. Every shiny fusion shows its colours.
- Wild Shiny Odds only apply to Pokemon met after changing it. Shiny Trainer Pokemon never touches partner trainers or your own Pokemon.
- Poke Radar+: the shiny chance keeps improving with the chain (1 in 20 at 100, 1 in 10 at 200), and Multi-Battle Radar makes radar battles doubles or triples.

**Pokemon and fusion**

- Fusion Screen: the DNA Splicers' preview shows both fusion orders with their names, types and real stats, and previews later evolutions on either side.
- Legendary Breeding: legendaries and legendary fusions can breed with any Pokemon that can breed.
- Evolution Lock covers every way to evolve and shows a padlock. Mist Stone, Devolution Spray and the Ability and Secret Capsules let you choose. The Move Relearner, Egg Move Tutor and the party's Change moves list more moves.
- Catching, hatching or evolving a fusion registers its head and its body in the Pokedex. KIF's gender colours, genderless icon and pizza icon show everywhere. Natures show as a small red + and blue - on the Skills page.
- Only KIF's six species changes are applied on top of PIF 6.8.2's data.

**Graphics, PC and quality of life**

- Big Pokemon Icons, Game's Font, Dark Mode for PIF's screens, Summary IVs/EVs and Fusion Preview.
- PC: Kuray Actions (also in the party menu), 26 ways to sort (BST is new), box locks, Buy Box and 160 extra wallpapers. Import and Export read 0.20.7's files safely. Hatch to PC is an option.
- Pause menu: PC, Heal, Kuray Shop and Tutor.net after Bag. Quicksave, Speed-up up to 10x, Quick Field Moves (Rock Climb, surfacing and Headbutt join Quick HMs) and Skip intro.

**Sprites, speed and updates**

- Import Sprites folder: drop in sprites, packs, folders or a .zip, and the next start moves everything into place. Identical sprites are skipped and changed ones ask once.
- All 576 base sprite sheets ship with the game. Sprite File Cache removes pauses in the PC and party.
- Frame rate up to 120 or Match monitor (experimental). Map loads are 2 to 3 times faster, the hitches between maps are gone, and long sessions no longer slow down.
- KIF updates itself (Options > System > Updates: Stable, Beta or Off): at start-up it asks Update now, What's new, Later or Skip this version, downloads only the files that changed, and never touches saves, mods, logs or your sprites. Works under Proton too.
- A Logs folder next to the game holds KIF_log.txt for each session and KIF_errorlog.txt for crashes. F12 restarts the game cleanly.

**Mods**

- Options > Mods: Browse the catalogs (KIF-Mods, KIF Mods (cody-png), Discord Mods and any catalog a modder adds) and install a mod with the mods it needs. WON'T START and CLASH warn about a mod made for another KIF version or one that doesn't work with a mod you have.
- Updates lists your mods with a newer version (only changed files download, settings kept), and the start-up asks about them. Modpacks install a set of mods at once. Share Code copies a code for the mods you have On (Mod Manager 2.0 codes work too).
- Installed switches each mod On or Off and opens its settings; Uninstall removes its folder and keeps its settings aside in case you come back to it.
- A mod is a .rb file, a folder or a .zip in the Mods folder. Its pictures and sounds stay in its own folder, so a mod never overwrites a game file. A broken mod is skipped and written to Logs/KIF_errorlog.txt.
- Mods written for KIF 0.20.7 and Mod Manager 2.0 still run on a compatibility layer.

**Fixes to PIF 6.8.2**

- Illusion never copies an Egg or a fainted Pokemon, and the battle box shows the real name once it breaks.
- A trainer's Pokemon that leaves through Wimp Out or Emergency Exit no longer pays out Exp.
- Prompt Nicknames Off also covers gifts, Bug Contest catches, triple fusions and K-Eggs.
- The Poke Mart deliveryman's Luvdisc comes on every playthrough. The Celadon Dept. Store's X-item clerk sells X Sp. Def instead of a "Thing".
- Every NPC who offers a trade shows the trade bubble until the trade is done.
- Comatose works for every Pokemon that has it, not only Komala. Losing to Misty no longer keeps her gym music playing in the Pokemon Center.
- One black shiny star no longer turns every later star black, the scroll arrow no longer stays on screen after some menus, and text with a % sign no longer crashes the debug console.
- PIF's download question and its announcement and installer prompts on the load screen are not shown.

**Not carried over from 0.20.7**

- The old auto-updater and sprite installer (replaced by the new updater, installers and Import Sprites), Shiny Finder.exe, Individual Custom Sprites (PIF has per-Pokemon sprites now), the in-game PBS editors and the unfinished K-Chests.

</details>
