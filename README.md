# Kuray Infinite Fusion (KIF)

Kuray Infinite Fusion (KIF) is a fork of Pokémon Infinite Fusion (PIF). It adds countless new features, including infinite colours for shinies, mod support (load your own mods from a "Mods" folder), a powerful AI (thanks to DemICE), and much more. Almost every feature can be turned on or off.

KIF is community-based and community-focused: made by the community, for the community, so that anyone can easily create new features for Infinite Fusion and have a better experience overall.

The original Pokémon Infinite Fusion was created by Chardub/Frogman using Pokémon Essentials. Please remember that the backbone of KIF (which is PIF) is still developed and maintained by Chardub/Frogman and the PIF team. If PIF dies, KIF is very likely to die as well.

KIF is **standalone**: you do not need Pokémon Infinite Fusion, and you should **NOT** install KIF on top of a PIF game.

This GitHub lets you see the game (open-source), contribute to its development with pull requests, and download the latest version.

## KIF Beta – now on PIF 6.8.2

KIF 0.20.7 was built on PIF 6.4.5. **KIF Beta** brings KIF's features to **PIF 6.8.2**, including its new content and the Hoenn additions.

- **Old KIF saves** load directly. Your settings, Pokémon and items carry over.
- **Bug reports:** if the game crashes, send the `Logs` folder from the game folder (`KIF_errorlog.txt` in it has the crash). Report KIF problems to the KIF community, **not** to the PIF developers.
- **New in KIF Beta:** an updater that downloads only what changed, sprite pack import, Modules (turn any part of KIF off), Settings Presets, Battle Info, the Fusion Screen and more – see [KIF_Features.md](KIF_Features.md).
- **Not carried over from 0.20.7**, because PIF 6.8.2 now does these itself or they no longer work:
  - Shiny Finder.exe;
  - Individual Custom Sprites (PIF now has per-Pokémon sprites);
  - option preset files from 0.20.7 (Settings Presets use a new format).

# Installation

Download the installer for your system from the [Releases page](https://github.com/cody-png/codybeta/releases/latest):

- **Windows 10 / 11:** [install_KIF.bat](https://github.com/cody-png/codybeta/releases/latest/download/install_KIF.bat)
- **Linux / Steam Deck:** [install_KIF.sh](https://github.com/cody-png/codybeta/releases/latest/download/install_KIF.sh)

1. Put the installer in the folder where you want the game.
2. Run it (Windows: double-click. Linux: double-click after ticking Properties > Permissions > "Is executable", or right-click > Run in Konsole).
3. It makes a **KIF** folder next to itself and downloads the game into it (about 4.5 GB free space needed while installing, 2 GB once done).
4. Start **InfiniteFusion.exe** in the KIF folder. On Linux it runs through Wine or Proton; the installer tells you how.

Your saves are in `%APPDATA%\KIF` and the installer never touches them. Running it again repairs a damaged install and keeps your saves, mods and imported sprites.

After that, KIF updates itself: at start-up it offers new versions and downloads only what changed (Options > KIF Settings > General settings > Updates).

# Features

**Every feature and option is explained in [KIF_Features.md](KIF_Features.md).** The guide follows the in-game menu order: Options → KIF Settings. It also ships with the game, next to InfiniteFusion.exe.

Highlights:

- **Shiny Revamp:** billions of possible shiny colours, with shiny dye fusing, gambling, and adjustable wild shiny odds.
- **Battles:** 2v2/3v3 battles, Auto-Battle, DemICE's AI and Endgame Challenge, level caps, Exp/EV/IV modes, Rocket Mode, Gen 9 mechanics (Frostbite, Drowsy, Snow), and challenge modes.
- **PC:** sorting, extra boxes and wallpapers, Self-Battles, Import/Export of Pokémon to share with other players, and Evolution Lock.
- **Kuray QoL:** PC, Heal and the Kuray Shop from the pause menu, plus K-Eggs, Tutor.net and Quicksave.
- **Fusion:** fusion preview, custom fusion base stats, dominant types, self-fusion boosts, and legendary-head breeding.
- **Look and feel:** big Pokémon icons, type icons and battle GUIs, fonts, and Dark Mode.
- **Modding support:** drop a mod's `.rb` file, its folder or its `.zip` into the `Mods` folder; switch mods On/Off in Options > KIF Settings > Mods.
- **Infinite save backups,** with named backups.

# Credits

- **Pokémon Infinite Fusion:** Chardub/Frogman and the PIF team.
- **Kuray Infinite Fusion:** Kurayami, with Reïzod, DemICE, Sylvi, Trapstarr, HungryPickle, Luminatron, Bluewuppo, JustAnotherU5er, Mirasein, FairyGodmother, Lolpy1, Rekt1029 and the whole KIF community.
- **KIF Beta (PIF 6.8.2):** cody-png.
- **Elite Battle DX:** Luka S.J. (EBDX), as adapted in KIF Multiplayer by Aleks, included with permission.
- Made with Pokémon Essentials.

KIF is a fan project and is not affiliated with or endorsed by the PIF team.

# Links

- Discord: https://discord.gg/kuray-hub-1121345297352753243 | https://discord.gg/vZUCRxDTPe
- Website: https://www.kurayinfinitefusion.com/
- Reddit: https://www.reddit.com/r/kurayhub/
- Twitter: https://twitter.com/kuray_hub
- YouTube: https://www.youtube.com/@kuraylab
- Twitch: https://www.twitch.tv/kurayamiblackheart
- Original KIF repository: https://github.com/kurayamiblackheart/kurayshinyrevamp
- Pokémon Infinite Fusion: https://github.com/infinitefusion/infinitefusion-e18 | https://discord.gg/infinitefusion
- Pokémon Essentials: https://github.com/Maruno17/pokemon-essentials

**Banned from the Kuray Hub Discord?** Use this form to ask for an unban or for information about the ban: https://forms.gle/TPCprf38ANmYNB5T8
