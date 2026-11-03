# Making mods for KIF

This guide is for people who write mods and for players who want to know what a mod can do.
It was written for API level 1 (the version of the mod calls described here). The event
tables and the permission table are produced from the game's own code, so they match it.

**Read this first.** A KIF mod is a Ruby program that runs inside the game, with the same
rights as the game and as you. There is no sandbox. KIF checks every mod, shows what it
says it needs, stops the common risky actions that a mod did not ask for, and keeps a
record. That makes honest mods easy to recognise and lazy attacks hard. It does not stop a
careful attacker, and this guide says which tricks get through (section 12). Only install
mods from people you trust. Turn a mod Off, or delete its folder, to remove it.

Contents

1. A mod in five minutes
2. mod.json
3. Events: reacting to the game
4. The events (generated list, 61 of them)
5. Hooking any game method
6. Adding content: menus, items, shops, encounters, text
7. Data your mod keeps
8. Timers
9. Working with other mods
10. Safe files, safe web, safe JSON
11. Permissions, the scan, the guard, trust
12. What this cannot stop
13. Worked examples
14. Publishing checklist
15. Mod Dev mode

---

## 1. A mod in five minutes

A mod is a folder in the game's `Mods` folder:

```
Mods/
  MyMod/
    mod.json     what the mod is, what it needs
    main.rb      its code (more .rb files are fine; list them in "scripts")
```

The fastest start: KIF Settings > System > Mod safety > Mod Dev mode > On, then Mod tools > Make a new
mod. It writes a working folder with a `mod.json`, a `main.rb` and a README. Edit `main.rb`,
restart the game (or use Reload mod in the tools for mods that only use the calls in this guide).

A first `main.rb`:

```ruby
KIF::API.on(:battle_start, "mymod_count") do |ctx|
  store = KIF::API.data(:save)                 # your own saved data
  store["battles"] = store.fetch("battles", 0) + 1
  KIF.log("MyMod: battle number #{store['battles']}")
end
```

Rules that keep the game healthy:

- React with events (section 3) or hooks (section 5). Do not copy game code and do not `alias` a
  game method yourself unless you must. If you must: alias OR `Module#prepend`, never both, and
  write it so that running the file twice does nothing bad (the game can run its scripts again with F12).
- Keep your own state in `KIF::API.data` (section 7), not in game objects the game saves.
- Write plain text with `KIF.log("...")` when you need to say something to the log.
- Say what you need in `mod.json` "permissions" (section 11). A mod that does more than it says is graded red.

## 2. mod.json

All keys are optional except what the catalog's checker asks for when you publish (id, name,
version, author, description). Unknown keys are ignored.

| Key | Type | Meaning |
|---|---|---|
| `id` | text | A short name for other mods and the catalog. a-z, 0-9, `_`, `-`. |
| `name`, `version`, `author`, `description` | text | Shown in KIF Settings > Mods. `description` may be a list of lines. |
| `scripts` | list of file names | The files to load, in order. Default: every .rb file. |
| `api_version` | whole number | The API level you wrote the mod for (now 1). A level above the game's: the mod is not started ("Needs a newer KIF"). None: an older mod; nothing is renamed or removed for it. |
| `permissions` | list of names | What the mod needs (section 11). Present, even empty: the mod is held to it. Absent: the mod is held to what its code was found to do. |
| `network_hosts` | list of host names, at most 10 | Where the mod may connect: `api.github.com` or `*.example.com`. No `http://`, no port, no IP number. With the `network` permission and no list: any host (graded red). |
| `permission_notes` | name -> sentence | One plain sentence per permission, at most 140 characters, shown when the player installs: "Uses the internet: checks for updates." |
| `requires_kif` | version test | `">=1.2.0"` or `">=1.2.0, <2.0"`. |
| `dependencies` | list of ids, or `{ "id": "kif_er", "version": ">=0.6" }` | Mods that must be installed and On. A version is checked against the other mod's version. |
| `load_after` | list of ids | Only an order; the named mods need not be installed. |
| `incompatible` | list of ids | Mods this one does not work with. |
| `replaces`, `locks`, `modules` | see KIF's mod rules | KIF features the mod takes over, settings it sets. |
| `catalog` | `owner/repo@branch` | Your own mod catalog, added to Browse. |
| `data_version` | whole number | For your own data migrations (`store.migrate`). |
| `hot_reload` | `false` | Opt out of Reload in Mod Dev mode. |
| `provides` | list of names | API names the mod offers to other mods (section 9). |
| `homepage` | text | Shown as text, never opened. |

## 3. Events: reacting to the game

```ruby
KIF::API.on(:damage_multipliers, "fire_boost", priority: KIF::API::LATE) do |ctx|
  ctx[:multipliers][:final_damage_multiplier] *= 1.1 if ctx[:user].hasType?(:FIRE)
end
KIF::API.on(:move_use) { |ctx| ctx.cancel!("not allowed") if ctx[:move].id == :SPLASH }
```

- `KIF::API.on(event, id = nil, priority: 0, once: false) { |ctx| ... }`. The `id` names your handler:
  the same id from the same mod replaces the older handler. `KIF::API.off(...)` removes one.
- `ctx[:field]` reads a field. `ctx[:field] = value` writes a field the tables below mark as
  changeable; a wrong kind or a number outside the range keeps the game's own value. In Mod Dev mode
  a bad write raises an error so you see it.
- `ctx.cancel!(reason)` works on events marked "Cancel: yes". `ctx.cancelled?` tells a later handler.
- Fields that are game objects (battle, battler, move, pokemon) are the live objects: use the
  game's own methods on them.
- Do not keep `ctx`: events that run very often reuse one object.
- Order: `FIRST`, `EARLY`, `NORMAL`, `LATE`, `LAST`, then `MONITOR` (always last, sees a frozen copy
  and cannot change anything). Equal priorities run in the mods' load order.
- A handler that raises is logged with your mod's name and skipped. The other handlers and the game go on.
  Five errors in a row, or 25 in a session, switch that one handler off for the session (KIF Settings > System > Mod safety > Mod tools shows it).
- An event nobody listens to costs one Hash lookup.
- Your own events: `KIF::API.define_event("mymod.boss_phase", fields: { boss: nil }, cancellable: true, doc: "...")`
  then `KIF::API.emit("mymod.boss_phase", boss: x)`. Names of mod events contain a dot; core names never do.
- `KIF::API.level`, `KIF::API.supports?(:event_name)`, `KIF::API.require_level(2)` (stops your mod cleanly
  when the game is older than you need).

## 4. The events

Each event says what it means, what a handler can read, what it can change and whether it can
cancel. Names marked "runs very often" fire many times a second: keep those handlers short.

### Loading

**`:mods_loading`**

Before the first mod loads. mods: the mod keys in load order.

- Fields you can read: `mods`
- Fields you can change: none
- Cancel: no

**`:mod_loaded`**

After all mods loaded, once per mod. Read the mod's key with ctx[:mod]
(ctx.mod is the mod whose handler runs).

- Fields you can read: `mod`, `json_id`, `name`, `version`, `ok`, `error`, `ms`, `files`
- Fields you can change: none
- Cancel: no

**`:mods_loaded`**

After every mod loaded. loaded / failed: lists of mod keys.

- Fields you can read: `loaded`, `failed`, `ms`
- Fields you can change: none
- Cancel: no

**`:data_loaded`**

After GameData.load_all and KIF's data steps. reload is false the first
time.

- Fields you can read: `reload`
- Fields you can change: none
- Cancel: no

**`:game_new`**

A new game started (Game.start_new finished).

- Fields you can read: `new_game_plus`
- Fields you can change: none
- Cancel: no

**`:game_loading`**

A save is about to load (Game.load). keys: the keys of the save.

- Fields you can read: `keys`
- Fields you can change: none
- Cancel: no

**`:game_loaded`**

A save finished loading.

- Fields you can read: none
- Fields you can change: none
- Cancel: no

**`:game_saving`**

The game is about to save (Game.save).

- Fields you can read: `path`, `safe`
- Fields you can change: none
- Cancel: no

**`:game_saved`**

The game saved. ok: false when the file could not be written.

- Fields you can read: `path`, `ok`
- Fields you can change: none
- Cancel: no

### Time and the map

**`:frame`** (runs very often)

After every Graphics.update, in the map, battles and menus. HOT.

- Fields you can read: `scope`, `frame_count`
- Fields you can change: none
- Cancel: no

**`:tick`** (runs very often)

Once per logic step (40 a second), after Graphics.update. HOT.

- Fields you can read: `scope`, `frame_count`
- Fields you can change: none
- Cancel: no

**`:map_update`** (runs very often)

Every frame on the map (Events.onMapUpdate). HOT.

- Fields you can read: none
- Fields you can change: none
- Cancel: no

**`:map_changed`**

The player moved to another map (Events.onMapChange).

- Fields you can read: `old_map_id`, `new_map_id`
- Fields you can change: none
- Cancel: no

**`:step_taken`** (runs very often)

The player took a step (Events.onStepTaken). Can not veto: use
:encounter_roll. HOT.

- Fields you can read: `event`, `map_id`, `x`, `y`
- Fields you can change: none
- Cancel: no

**`:interact_start`**

An event is about to start (Game_Event#start).

- Fields you can read: `event`, `map_id`
- Fields you can change: none
- Cancel: yes, the event does not start

**`:interact_check`**

The player pressed the action key (Game_Player#check_event_trigger_there).

- Fields you can read: `triggers`
- Fields you can change: none
- Cancel: yes, no interaction happens

**`:encounter_roll`**

Does a wild encounter happen now? (PokemonEncounters#encounter_triggered?)

- Fields you can read: `encounters`, `enc_type`, `repel_active`, `by_step`, `map_id`
- Fields you can change: `result` (bool)
- Cancel: no

**`:encounter_choose`**

Which wild Pokemon appears: [species, level] or nil
(PokemonEncounters#choose_wild_pokemon).

- Fields you can read: `encounters`, `enc_type`, `chance_rolls`, `map_id`
- Fields you can change: `result` (obj)
- Cancel: no

### Items and shops

**`:item_stored`**

An item went into the bag (PokemonBag#pbStoreItem).

- Fields you can read: `bag`, `item`, `qty`
- Fields you can change: none
- Cancel: no

**`:shop_stock`**

The list of items a city's Poke Mart sells (Array of item Symbols).

- Fields you can read: `city`
- Fields you can change: `result` (array)
- Cancel: no

**`:item_found`** (extra)

An item is about to be given from the ground or a gift (pbItemBall).

- Fields you can read: `item_name`
- Fields you can change: `item` (obj), `quantity` (int, 0..9999)
- Cancel: yes, nothing is given

### Battle

**`:battle_start`**

A battle is starting (PokeBattle_Battle#pbStartBattle).

- Fields you can read: `battle`, `wild`, `trainer`, `double`
- Fields you can change: none
- Cancel: no

**`:battle_loop`**

The intro and send-outs are done; the turns begin (pbBattleLoop).

- Fields you can read: `battle`
- Fields you can change: none
- Cancel: no

**`:battle_end`**

The battle is about to end. decision: 1 win, 2 lose, 3 flee, 4 caught, 5
draw.

- Fields you can read: `battle`, `decision`, `can_lose`
- Fields you can change: none
- Cancel: no

**`:battle_ended`**

The battle has ended (after pbEndOfBattle).

- Fields you can read: `battle`, `decision`
- Fields you can change: none
- Cancel: no

**`:turn_start`**

A new turn: the command phase starts (pbCommandPhase).

- Fields you can read: `battle`, `turn`
- Fields you can change: none
- Cancel: no

**`:attack_phase`** (extra)

The attack phase of a turn starts (pbAttackPhase).

- Fields you can read: `battle`, `turn`
- Fields you can change: none
- Cancel: no

**`:round_end`**

The end-of-round phase starts (pbEndOfRoundPhase).

- Fields you can read: `battle`, `turn`
- Fields you can change: none
- Cancel: no

**`:round_ended`**

The end-of-round phase is over.

- Fields you can read: `battle`, `turn`
- Fields you can change: none
- Cancel: no

**`:move_use`**

A battler is about to use a move (PokeBattle_Battler#pbUseMove).

- Fields you can read: `battler`, `battle`, `choice`, `move`, `special_usage`
- Fields you can change: none
- Cancel: yes, the move is not used (no PP change)

**`:move_used`**

A battler used a move.

- Fields you can read: `battler`, `battle`, `choice`, `move`, `special_usage`
- Fields you can change: none
- Cancel: no

**`:battler_faint`**

A battler is about to faint (pbFaint).

- Fields you can read: `battler`, `battle`, `show_message`
- Fields you can change: none
- Cancel: no

**`:battler_fainted`**

A battler fainted.

- Fields you can read: `battler`, `battle`
- Fields you can change: none
- Cancel: no

**`:switch_in`**

A battler entered the field (pbEffectsOnSwitchIn).

- Fields you can read: `battler`, `battle`, `switch_in`
- Fields you can change: none
- Cancel: no

**`:battler_init`**

A battler's effects were reset (pbInitEffects). baton_pass: true when a
Baton Pass keeps some.

- Fields you can read: `battler`, `battle`, `baton_pass`
- Fields you can change: none
- Cancel: no

**`:damage_multipliers`** (runs very often)

The damage multipliers of one hit. Change
multipliers[:base_damage_multiplier], [:attack_multiplier],
[:defense_multiplier], [:final_damage_multiplier] (Float above 0, at most
16). HOT.

- Fields you can read: `move`, `user`, `target`, `num_targets`, `type`, `base_damage`
- Fields you can change: `multipliers` (hash)
- Cancel: no

**`:type_effectiveness`** (runs very often, extra)

Effectiveness of one type against one type (pbCalcTypeModSingle). HOT.

- Fields you can read: `move`, `move_type`, `def_type`, `user`, `target`
- Fields you can change: `result` (int, 0..64)
- Cancel: no

**`:accuracy_check`** (extra)

Does the move hit? (pbAccuracyCheck)

- Fields you can read: `move`, `user`, `target`
- Fields you can change: `result` (bool)
- Cancel: no

**`:crit_check`** (extra)

Is it a critical hit? (pbIsCritical?)

- Fields you can read: `move`, `user`, `target`
- Fields you can change: `result` (bool)
- Cancel: no

**`:hit_count`** (extra)

How many times a move hits (pbNumHits).

- Fields you can read: `move`, `user`, `targets`
- Fields you can change: `result` (int, 1..10)
- Cancel: no

**`:exp_gain`**

Experience is about to be given after a battle (pbGainExp).

- Fields you can read: `battle`
- Fields you can change: none
- Cancel: no

**`:exp_gained`**

Experience was given.

- Fields you can read: `battle`
- Fields you can change: none
- Cancel: no

**`:money_gain`** (extra)

Prize money is about to be given (pbGainMoney).

- Fields you can read: `battle`
- Fields you can change: none
- Cancel: no

**`:ai_score_move`**

The AI's score for one move. PIF scores are absolute; a DemICE-style AI
returns changes, so add to the score you get.

- Fields you can read: `ai`, `move`, `user`, `target`, `skill`
- Fields you can change: `score` (int, -100000..100000)
- Cancel: no

**`:ai_rough_damage`** (extra)

The AI's guess of the damage a move does (pbRoughDamage).

- Fields you can read: `ai`, `move`, `user`, `target`, `skill`
- Fields you can change: `result` (int, 0..1000000)
- Cancel: no

**`:ai_choose`** (extra)

The AI is about to choose a command for a battler.

- Fields you can read: `ai`, `battler_index`, `battle`
- Fields you can change: none
- Cancel: yes, your handler already registered a command; the AI does nothing

### Pokemon and fusion

**`:fusion_done`**

Two Pokemon were fused (pbFuse). result: the fusion.

- Fields you can read: `body`, `head`, `splicer`, `result`
- Fields you can change: none
- Cancel: no

**`:unfuse_done`**

A fusion was split (pbUnfuse).

- Fields you can read: `pokemon`, `party_position`, `pc_position`, `result`
- Fields you can change: none
- Cancel: no

**`:fusion_before`** (extra)

A fusion is about to happen.

- Fields you can read: `body`, `head`, `splicer`
- Fields you can change: none
- Cancel: yes, no fusion

**`:pokemon_added`** (extra)

A Pokemon was added to the party or the PC (pbAddPokemon).

- Fields you can read: `pokemon`, `result`
- Fields you can change: none
- Cancel: no

**`:level_changed`** (extra)

A Pokemon changed level (pbChangeLevel).

- Fields you can read: `pokemon`, `old_level`, `new_level`
- Fields you can change: none
- Cancel: no

**`:stats_calculated`** (extra)

A Pokemon's stats were recalculated (Pokemon#calc_stats). Edit pokemon.stats
on the live object.

- Fields you can read: `pokemon`
- Fields you can change: none
- Cancel: no

**`:wild_battle_start`** (extra)

A wild battle is about to start (pbWildBattle).

- Fields you can read: `can_run`, `can_lose`
- Fields you can change: `species` (obj), `level` (int, 1..100)
- Cancel: no

### Screens

**`:sprite_update`** (runs very often, extra)

A map character sprite updated (Sprite_Character#update). HOT.

- Fields you can read: `sprite`, `character`
- Fields you can change: none
- Cancel: no

**`:sprite_dispose`** (extra)

A map character sprite is being disposed.

- Fields you can read: `sprite`, `character`
- Fields you can change: none
- Cancel: no

**`:pause_menu_build`**

The pause menu's KIF rows are built. Change entries (an Array of
KIF::PauseMenu::Entry) or use ctx.hide(id), ctx.relabel(id, text),
ctx.move(id, order).

- Fields you can read: none
- Fields you can change: `entries` (array)
- Cancel: no

**`:summary_page_drawn`** (extra)

A Summary page was drawn. Draw on overlay (a Bitmap).

- Fields you can read: `scene`, `pokemon`, `page`, `overlay`
- Fields you can change: none
- Cancel: no

**`:party_panel_drawn`** (extra)

A party panel was drawn.

- Fields you can read: `panel`, `pokemon`, `bitmap`
- Fields you can change: none
- Cancel: no

**`:databox_drawn`** (extra)

A battle data box was drawn.

- Fields you can read: `databox`, `battler`, `bitmap`
- Fields you can change: none
- Cancel: no

**`:storage_overlay_drawn`** (extra)

The PC's information overlay was drawn.

- Fields you can read: `scene`, `selection`, `bitmap`
- Fields you can change: none
- Cancel: no

**`:scene_open`** (extra)

The scene changed (seen in the frame hook).

- Fields you can read: `scene`, `name`
- Fields you can change: none
- Cancel: no


---

## 5. Hooking any game method

For what the events do not cover. The engine keeps every hook on a method in one wrapper, so mods
do not stack on each other and one failing hook does not stop the rest.

```ruby
KIF::API.around("PokeBattle_Battler#pbUseMove") { |call| call.proceed }
KIF::API.before("Game_Event#start", "mymod_id") { |call| call.skip!(false) if bad? }
KIF::API.after("pbItemBall") { |call| KIF.log("gave #{call.args[0]}") }
KIF::API.unhook("PokeBattle_Battler#pbUseMove", "mymod_id")
KIF::API.hooks               # every hook, with the mod that made it
KIF::API.hooked?("Graphics.update")
```

- Target: `"Class#method"` (instance method), `"Class.method"` (class method), `"Object#pbGlobalFunction"`,
  `[Class, :method]` or `[Class, :method, :singleton]`.
- `call` has: `receiver`, `args` (change it in before/around), `kwargs`, `block`, `proceed(*new_args)`
  (runs the next hook or the game's method), `result` / `result=`, `skip!(value)` (in `before`: do not run the method and return value),
  `called?`.
- `around`: the block's value is the method's result. `before`: may change `call.args` or call `skip!`.
  `after`: may set `call.result`.
- `defer: true` waits for a method another mod defines (retried when all mods have loaded).
- A target that does not exist is logged once and gives nil (Mod Dev mode raises `KIF::API::HookError`).
- The engine picks alias or prepend for the method, by one rule, and never both. A mod that REPLACES a method
  (a plain `def`) wins and is listed in `KIF::API.collisions`.
- Refused as targets, so the API is not a way around the guard: `Kernel`, `File`, `IO`, `Dir`, `Marshal`, `Process`,
  `ENV`, threads, native-call classes and KIF's own security modules.

## 6. Adding content

Everything here remembers which mod made it (the inspector shows it; a reload takes it back). Anything
that needs the game's data (items, evolutions, encounters, texts) is queued and applied after the data loads.

```ruby
KIF::API::PauseMenu.add(:my_row, "My row", handler: ->(scene) { pbMessage("Hello"); :stay }, condition: -> { true }, order: 100)
KIF::API::PauseMenu.hide(:kif_pc);  KIF::API::PauseMenu.relabel(:kif_pc, "Box");  KIF::API::PauseMenu.move(:kif_pc, 5)
KIF::API::PartyMenu.add(:my_row, "My action", handler: ->(screen, pkmn, idx) { })
KIF::API::BattlerState.register("rage", 0, reset_on: :switch_in)    # :switch_in | :battle_end | :never
KIF::API::BattlerState.set(battler, "rage", 3);  KIF::API::BattlerState.get(battler, "rage")
KIF::API::Shops.add(:PEWTER, [:ETHER]);  KIF::API::Shops.add(:all, [:POTION], if: ->(ctx) { true })
KIF::API::Shops.add_kuray(:MYITEM, 5000, 2500, false)
KIF::API::Items.register(:MYSTONE, name: "My Stone", description: "...", price: 1000,
                         icon: "icons/mystone.png", handlers: { use_on_pokemon: proc { } })
KIF::API::Tune.set("Pokemon::EV_LIMIT", 999);  KIF::API::Tune.revert(mod)
KIF::API::AI.score("my_id", priority: KIF::API::LATE) { |ctx| ctx[:score] += 10 }
KIF::API::Fusion.after("my_id") { |ctx| }
KIF::API::Text.swap("Some game text") { "Other text" };  KIF::API::Text.set(:item_name, :POTION, "Tonic")
KIF::API::Encounters.rate("my_id") { |ctx| ctx[:result] = true }
KIF::API::Encounters.add_slot(map: 5, type: :Land, species: :PIKACHU, min_level: 3, max_level: 5, chance: 10)
KIF::API::Evolutions.register_method(:MyMethod, hash);  KIF::API::Evolutions.add(:RATTATA, to: :RATICATE, method: :Level, parameter: 20)
KIF::API::Sprites.decorate(:character) { |sprite, character| };  KIF::API::Sprites.on_dispose { |sprite, character| }
KIF::API::Theme.color(:acc);  KIF::API::Theme.register_color("name", [r, g, b]);  KIF::API::Fonts.available
```

A mistake in a menu `condition:`, `label:` or `handler:` is logged once with your mod's name and that
row is skipped; the menu still opens.

## 7. Data your mod keeps

```ruby
store = KIF::API.data(:save)     # this save file's data for your mod
store = KIF::API.data(:global)   # this install's data for your mod
store["gold"] = 5;  store.fetch("gold", 0);  store.update("a" => 1, "b" => [1, 2])
store.delete("gold");  store.key?("a");  store.keys;  store.to_h;  store.clear
store.version;  store.migrate(to: 2) { |old| old.merge("new" => 1) }
KIF::API.data(:save, mod: "other_mod")    # another mod's data: a frozen copy, read only
```

- Plain data only: nil, true, false, whole numbers, finite decimals, text (UTF-8, at most 64 KB), lists and
  hashes (keys become text), nested at most 8 deep. A mod may hold 256 KB; all mods 2 MB in saves and 4 MB global.
  Anything else is not stored, is logged once, and raises `KIF::API::PlainDataError` in Mod Dev mode.
- Nothing you store is run or loaded with Marshal. Saves hold plain core types only, under one key, so a
  save loads in the plain game and without your mod.
- Data of a mod that is not installed stays in the save and comes back if the mod does. `KIF::API.data_orphans`
  lists it; `KIF::API.data_forget(key, scope)` removes it. Nothing is removed by itself.
- `:global` is a file in the save folder, written whole or not at all.

## 8. Timers

```ruby
KIF::API.after(steps: 120) { }                          # once, in 120 logic steps
KIF::API.after(seconds: 3, id: "mymod_id") { }          # once, in 3 seconds
KIF::API.every(seconds: 10, scope: :always) { }
KIF::API.when_idle { }                                  # once, at the next moment the map is quiet
KIF::API.map_idle?
t = KIF::API.after(steps: 10) { };  t.cancel
```

Units are logic steps, 40 a second (not drawn frames). `scope: :map` (default) counts only while the map is
idle, `:always` everywhere, `:battle` only in battle. The same `id` from the same mod replaces the older timer. At most
500 timers per mod. Timers are not saved and go away when the mod is unloaded. A timer that raises is logged
once and cancelled after five errors in a row.

## 9. Working with other mods

```ruby
KIF::API.when_loaded("kif_er") { |info| ... }       # now if loaded, else when all mods have loaded
KIF::API.when_defined("Class#method") { ... }       # the same for a method another mod defines
KIF::API.provide("mymod.kit", object, version: 1)   # offer an API to other mods
KIF::API.api_of("mymod.kit");  KIF::API.provided
KIF::API.mods;  KIF::API.mod("kif_er");  KIF::API.mod_loaded?("kif_er");  KIF::API.mod_version("kif_er")
KIF::API.collisions                                 # "mod X replaced Class#m"
```

The order of loading does not matter for `when_loaded`; you do not need `load_after`.

## 10. Safe files, safe web, safe JSON

`KIF::Safe` is what an honest mod calls instead of raw file and network code. It is KIF's own code, so it
never trips the guard, and it adds limits of its own.

```ruby
KIF::Safe.write_text("notes.txt", "hello")             # in your mod's own data folder
KIF::Safe.read_text("notes.txt")
KIF::Safe.write_json("settings.json", { "volume" => 3 });  KIF::Safe.read_json("settings.json", {})
KIF::Safe.read_own("data/table.txt")                   # a file inside your own mod folder (read only)
KIF::Safe.json_parse(text)                             # plain data, never run as code
r = KIF::Safe.http_get("https://api.github.com/repos/cody-png/kif-mods", timeout: 10)   # { status:, body: }
KIF::Safe.http_post_json(url, { "a" => 1 })
KIF::Safe.open_url("https://example.org")              # asks the player first
```

- Names must be plain relative names (`KIF.safe_rel_path?`). A file is at most 1 MB (up to 8 MB with `max:`), a mod
  has at most 64 files and 32 MB. Writes go to a temporary file first, so a file is whole or not there. A link planted
  in the data folder does not lead out of it.
- JSON is read with a reader that never runs code, at most 16 deep, plain data only. Never use the game's `JSON` on
  text from outside: it can run code.
- `http_*` need the `network` permission and the host in `network_hosts`. https only (loopback for tests), no
  redirect is followed, the answer stops at `max_bytes` (2 MB by default).
- `open_url` replaces `system("start", url)`. It takes https only and asks the player (default No).

## 11. Permissions, the scan, the guard, trust

**Permissions.** What a mod can ask for in `mod.json`:

| Name | Colour when used | What it means |
|---|---|---|
| `network` | yellow | Uses the internet |
| `programs` | red | Starts other programs on your computer |
| `native` | red | Calls Windows or system code directly |
| `game_files` | yellow | Changes files in the game folder |
| `save_files` | yellow | Changes your save files and KIF settings |
| `outside_files` | red | Reads or changes files outside the game |
| `environment` | yellow | Reads your computer's settings |
| `clipboard` | yellow | Reads or sets your clipboard |
| `load_code` | yellow | Loads code from outside its own folder |
| `marshal` | yellow | Reads saved-object files |
| `eval` | none (information only) | Builds code from text while running |
| `objectspace` | none (information only) | Looks through everything the game has loaded |

Stopped when not listed (Normal mode): `network`, `programs`, `native`, `game_files`, `save_files`, `outside_files`, `load_code`. The others are only noted.

Two permissions are quieter than they look. `game_files` lets a mod rewrite the game's own scripts (KIF's included) for the next start, and `save_files` lets it edit saves, settings and KIF's own lists (the trust file too). They are yellow because many honest mods keep a small file there; treat them as serious, and prefer `KIF::Safe` (the mod's own data folder needs neither).

**The scan** (`KIF::ModCheck.scan`, also used by Publish a mod). It reads a mod's code and files without running
anything and grades it:

- green: nothing to tell the player. yellow: worth a look. red: does something dangerous, or more than it says.
- Informational findings never change the colour. A permission you list does not lower its colour (the player should
  still see "red: starts programs"); it only removes "does more than it says".
- With a `permissions` list, code that uses something not on it is an extra finding (R30, red for the internet, programs, native code and outside
  files; yellow for the others). A listed permission that the code never uses is information (R31).

| Rule | What it finds | Colour |
|---|---|---|
| R01 | Starts other programs: `system`, `spawn`, `exec`, backticks, `IO.popen`, `Open3`, `Process.spawn`, `open("\|cmd")` | red |
| R02 | Calls Windows or system code: `Win32API`, `Fiddle`, `FFI` | red |
| R03 | Uses the internet: `Net::HTTP`, sockets, `HTTPLite`, `open-uri`, the game's download helpers | red (yellow when `network_hosts` is given) |
| R04 | Writes or deletes files | yellow |
| R05 | Reads or changes files outside the game: home folder, drive paths, AppData, Desktop | red |
| R06 | Reads your computer's settings: `ENV`, `Etc` | yellow |
| R07 | Builds code from text while running: `eval`, `class_eval` with text | yellow (information for `class_eval <<-RUBY, __FILE__, __LINE__`) |
| R08 | Reads saved-object files: `Marshal.load`, `YAML.load` | yellow (information for `Marshal.load(Marshal.dump(x))`) |
| R09 | Looks through everything the game has loaded: `ObjectSpace` | information |
| R10 | Loads code from outside its own folder: `load`/`require` of a non-.rb file, an absolute path, an unknown library | yellow (information for your own `load File.join(ROOT, ...)`) |
| R11 | Hides what the code does: `Base64`, `unpack("m")`, `pack("c*")`, long runs of `\x..`, a very long line with code behind spaces, a 200-character coded string, `send`/`const_get` with a built name, `super_method` | red |
| R12 | Tries to change KIF's protection: `KIF::ModGuard`, `TracePoint`, `at_exit`, reopening `File`, `Kernel`... | red |
| R13 | Sets itself up to run outside the game: Startup folder, `reg add`, .bat/.cmd/.ps1/.vbs names | red |
| R14 | `unless method_defined?` around a `def` (stops working after F12) | yellow |
| R16 | The folder holds a program file, an archive, a link, a hidden file, a very large file | red or yellow |
| R17 | Text direction tricks in a .rb file | red |
| R20 | `exit!`, `abort`, `fork`, `Process.kill` | yellow |
| R21 | `Input.clipboard` | yellow |
| R30 / R31 | Does more than `permissions` says / asks for more than it uses | red or yellow / information |
| R32 | A problem in mod.json: unknown permission name, bad `network_hosts`, bad `api_version` | yellow |

The scan has no false red on the first-party mods (KIF: Elite Redux, Megas, Differentiating Duplicates and the others); if a rule ever
paints an honest mod red, the rule is made weaker, never the mod excused.

**The guard** (`KIF::ModGuard`). KIF watches the calls that can hurt a player and works out which mod made each call from the
file the code came from (the nearest frame that is not Ruby's own library, an `eval` text, or the guard decides). KIF's own and the game's code is
never stopped. A mod that does not hold the permission:

- Normal (default): is stopped for programs, native code, the internet, files outside its own folders and loading code from elsewhere; only noted for the
  environment, clipboard, Marshal and ObjectSpace.
- Strict: is stopped for everything it did not list. Warn only: only noted. Off: nothing is noted or stopped.
- A stop raises `KIF::ModGuard::Denied` (an ordinary `StandardError`) with a plain message: `KIF stopped mod "X": it tried to start a program. Options > Mods > X to allow it.` ("Options > Mods" is KIF Settings > Mods.) The first stop of a session also shows a message on the map.
- What a mod holds: its `permissions`; for an older mod, what its code was found to do; plus what the player added; or everything if the player chose
  "Allow anything" for that mod in KIF Settings > Mods.
- The Mod protection setting is read from `KIF_ModTrust.json` (the Options row writes it there), not from the player's settings object, and the guard's own switches, the trust table and the list of mod folders refuse to be changed or read by a mod's code. Only code that gets around the check with Ruby reflection can reach them (section 12).
- A mod's own folder and its data folder (`KIF::Safe.mod_dir`) are always free to read and write. A program file (.exe, .bat ...) may not be written anywhere.
- A door that was bypassed or redefined is found when a mod finishes loading (the mod is marked TAMPERED) and again every 30 seconds (logged).

**Trust** (KIF Settings > Mods). Each mod has a state in `KIF_ModTrust.json` in the save folder:

- Mods that were already installed when this check arrived are let in once ("grandfathered").
- A new mod is scanned before it loads. Green: approved. Yellow: it loads and the player gets one notice on the map. Red (or withdrawn): it is held, its code does not run, and the
  list says NEEDS OK. The player reads what it can do (KIF Settings > Mods > the mod (USE) > Review and allow) and allows it for the next start.
- A mod whose files changed is scanned again; if it now needs more or grades worse it is treated like a new mod.
- With Mod protection on Off or Warn only nothing is held back.
- The list shows OK (green), CHECK (yellow), RISK (red), NEEDS OK, TAMPERED beside On/Off. "What it can do", "Allow anything" and "Blocked actions" are in the mod's menu.

**Catalog installs.** The file list is read at one commit and the files come from that same commit. Every file's hash is checked, and the install is all or nothing. A
link in a catalog (git mode 120000 or 160000) or in a zip refuses the whole mod. A record `.kif_provenance` stays in the mod's folder (repo, commit, date, every file's hash); at each
start the mod's files are compared with it and a changed or extra file reads "Changed since it was installed". After the download and before anything is moved in, the files are scanned: a red
mod, a mod that does more than it says, or a withdrawn mod is asked about once (default No), and an update asks only about what is new. A Yes means the mod is not held at the next start.

**Reviewed and withdrawn lists.** A catalog repository may hold two optional files at its root, read at most once a day from the branch head and kept in the save folder. Only the KIF catalogs (cody-png/kif-mods and cody-png/kif-discord-mods) and a folder the player named are read for them; a catalog a mod adds through its own `catalog` key cannot call its own mod reviewed or another mod withdrawn. A mod that is installed and then appears on the withdrawn list is held from the next start and the player is told:

`reviewed.json`: `{ "format": 1, "mods": { "<mod id>": { "fingerprint": "<40 hex>", "version": "1.2.0", "reviewed": "2026-11-01", "result": "green", "note": "short text" } } }`

`revoked.json`: `{ "format": 1, "revoked": [ { "id": "<mod id>", "fingerprint": "<40 hex, optional>", "versions": "<=1.1.0 (optional)", "reason": "text, at most 140", "since": "2026-11-01" } ] }`

The fingerprint is the SHA-1 of the sorted lines `<git blob sha> <path>` of the mod's files. `ruby tools/mod_fingerprint.rb <mod folder>` in the test kit prints it with a ready entry. A mod that matches
`reviewed.json` shows "Reviewed <date>"; one that differs shows "Changed since it was reviewed". A mod that matches `revoked.json` is held and the install asks first.
Text from these files is cleaned and size-limited before it is shown.

## 12. What this cannot stop

Said plainly, because players will rely on it. These are what the guard and the scan do **not** catch (kit test `s_f_modapi_attacks` keeps the list):

Not stopped in the attack test (it ran):

1. Code run with `eval` and a file name of its own (`eval(text, nil, "x.rb")`): the code then belongs to nobody. The scan flags the `eval` (yellow).
2. Skipping a door with `Kernel.instance_method(:system).super_method.bind_call(...)`. The scan flags `super_method` (red); the guard cannot see it.
3. Turning the guard off from inside with Ruby reflection (`ObjectSpace` to find `KIF::ModGuard`, then `instance_variable_set`). The call made in between is not undone. The guard finds the flipped switch when the next mod finishes loading or within 30 seconds, and puts it back.

Stopped in the attack test: `system`, backticks, `send` with a joined or escaped name, `method(:system).call`, `eval` of built, base64 or packed text, a thread, `open("|cmd")`, `IO.popen`
reached with `const_get`, `TCPSocket` reached with a built name, `Open3`, `FileUtils.cp` through `send`, `require` of a file outside, `Process.method(:spawn)`.

Not seen by design:

4. `require_relative` (a door cannot tell which file calls it). `load` and `require` are guarded.
5. Game helpers that do file or network work for their caller and are not listed as doors, reached through Ruby reflection (`send`, `method(:x).call`, `instance_variable_get`, `const_get`).
6. Changing game state in memory (money, Pokemon, flags), which the game then saves; patching KIF or the game, which is what modding is.
7. Threads and endless loops, memory use, and text `eval` (a wrapper would change which variables the code sees).
8. Reading: any mod may read the game folder and the save folder (other saves, settings). `Marshal.load` is only noted in Normal mode.
9. Native code once a mod holds `native`; whatever a started program does once a mod holds `programs`.
10. Mods that another loader starts (Mod Manager's own mods load themselves): they are scanned and listed but not guarded.
11. A mod that draws a fake message or asks for a password on screen. No check can tell.
12. A race: a link swapped in between the moment the guard looks at a path and the moment the file opens. The guard follows links when it looks; it cannot hold the file still.

If you only remember one thing: the guard and the scan make honest mods easy to recognise and stop the lazy attacks. A motivated attacker with Ruby skill gets around them. The complete protections
are not installing mods from strangers, the reviewed list, and your own judgment.

## 13. Worked examples

**A battle rule.** Fire moves hit 10% harder, and Splash does nothing (no permissions needed):

```ruby
KIF::API.on(:damage_multipliers, "mymod_fire", priority: KIF::API::LATE) do |ctx|
  ctx[:multipliers][:final_damage_multiplier] *= 1.1 if ctx[:user].hasType?(:FIRE)
end
KIF::API.on(:move_use, "mymod_nosplash") { |ctx| ctx.cancel!("Splash is disabled") if ctx[:move].id == :SPLASH }
```

**The map.** Count steps and tell the player every 1000:

```ruby
KIF::API.on(:step_taken, "mymod_steps") do |ctx|
  s = KIF::API.data(:save)
  s["steps"] = s.fetch("steps", 0) + 1
  KIF::API.when_idle { pbMessage("#{s['steps']} steps!") } if (s["steps"] % 1000).zero?
end
```

**A menu row.**

```ruby
KIF::API::PauseMenu.add(:mymod_stats, "My stats", order: 200,
  handler: ->(scene) { pbMessage("Battles: #{KIF::API.data(:save).fetch('battles', 0)}"); :stay })
```

**An item and a shop.**

```ruby
KIF::API::Items.register(:MYSTONE, name: "My Stone", description: "A test stone.", price: 1000, icon: { item: :FIRESTONE })
KIF::API::Shops.add(:PEWTER, [:MYSTONE])
```

**Your own data and a migration.**

```ruby
store = KIF::API.data(:global)
store.migrate(to: 2) { |old| old.merge("volume" => old.fetch("vol", 3)) } if store.version < 2
```

**The internet, the right way.** mod.json:

```json
{ "id": "update_check", "name": "Update Check", "version": "1.0.0", "author": "You", "description": "Tells you about a new release.",
  "api_version": 1, "permissions": ["network"], "network_hosts": ["api.github.com"],
  "permission_notes": { "network": "Asks GitHub for the newest release number." } }
```

main.rb:

```ruby
KIF::API.after(seconds: 5, scope: :always) do
  begin
    r = KIF::Safe.http_get("https://api.github.com/repos/cody-png/kif-mods/releases/latest", timeout: 10)
    info = KIF::Safe.json_parse(r[:body]) if r[:status] == 200
    KIF.log("Newest release: #{info['tag_name']}") if info
  rescue KIF::Safe::Error, KIF::ModGuard::Denied => e
    KIF.log("Update check failed: #{e.message}")
  end
end
```

**Files.** `KIF::Safe.write_json("settings.json", { "volume" => 3 })` needs no permission; `File.write("Mods/MyMod.cfg", ...)` needs `game_files` and
`File.write("C:/x", ...)` needs `outside_files` (red).

## 14. Publishing checklist

1. `mod.json` has id, name, version, author, description, `api_version`, and `permissions` that match what the code does (the scan shows R30/R31).
2. `network_hosts` lists every host (no wildcards you do not need), and `permission_notes` explains each permission in one sentence.
3. The scan is green or yellow. If it is red, the reason is something the mod really does, and the description says why.
4. No program files (.exe .dll .bat ...), no archives, no links, no hidden files, no file over 25 MB (100 MB in all).
5. Your files are written with `KIF::Safe` or into the mod's own folder; no `eval` of text from outside; no `Marshal.load` of files from outside.
6. The code is safe to load twice (F12), has no `alias` AND `prepend` on the same method, and does not replace game methods when an event or a hook would do.
7. It works with Mod Dev mode On (bad field writes raise there) and with the mod removed (saves load without it).
8. Use KIF Settings > Mods > Publish a mod: it runs the catalog's checks and shows the scan before anything is uploaded.
9. Want it listed as reviewed? Run `ruby tools/mod_fingerprint.rb <folder>` (test kit) and send the entry with your pull request.

## 15. Mod Dev mode

KIF Settings > System > Mod safety > Mod Dev mode: On. It makes the API stricter and adds KIF Settings > System > Mod safety > Mod tools:

- Bad field writes, unknown event names, bad hook targets and non-plain data raise errors (otherwise they are logged once and ignored).
- Events and hooks inspector: every event with its subscribers, calls, average and slowest time, errors and state; wrapped game methods with their mods.
- Trace: the last emits with their time (`Logs/KIF_modapi_trace.txt`).
- Reload mod / Reload all mods: removes what the mod added through the API (handlers, hooks, timers, registry entries, provided APIs, tuning), loads its scripts again and applies the
  registries again. It does not undo raw `alias`, `def`, `class_eval`, `Events.on...+=`, data-load steps or settings the mod made; the result says in how many places the mod patches the game
  directly, and a restart is the only clean reload for those. A mod with `"hot_reload": false` is skipped.
- Make a new mod: writes `Mods/<Name>/` with a working `mod.json`, `main.rb` and README.
- Write API reference: `Logs/KIF_API_Reference.txt` (every event and call) and a hook report `Logs/KIF_hooks.txt`.

Setting Mod protection to Warn only while you test lets a new red mod load instead of being held.
