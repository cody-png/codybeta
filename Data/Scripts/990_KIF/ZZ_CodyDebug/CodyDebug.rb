#===============================================================================
# Cody Debug – a small testing menu (debug mode only, F7 on the map)
#   Self-contained: this folder can be zipped and dropped into another copy's
#   Data/Scripts/990_KIF. Nothing here runs unless the game is in debug mode.
#
#   Warp      – any map by name (type to filter), a town (fly map, anywhere),
#               recent warps, or a shuffled door's doorstep / place
#   Give      – packs (starter kit, badges, field-move tools, travel items,
#               balls & medicine, money) or any item by name
#   Party     – heal, set a level, add any Pokémon or fusion, max IVs
#   Entrances – where this map's doors lead (and go through one), this map's
#               level numbers, mark doors found / forget them
#   Cheats    – no wild encounters, trainers don't spot you, walk through walls
#===============================================================================
module KIF
  module CodyDebug
    KEY = :F7
    RECENT_MAX = 8

    class << self
      attr_accessor :no_encounters, :no_sight, :ghost
      def recent; @recent ||= []; end
    end

    module_function

    def enabled?
      return $DEBUG ? true : false
    end

    #---------------------------------------------------------------------------
    # Menu plumbing: a list with a help line, Back returns nil
    #---------------------------------------------------------------------------
    def choose(title, rows)
      return nil if rows.empty?
      msgwin = pbCreateMessageWindow
      names = rows.map { |r| r[0] }
      helps = rows.map { |r| r[1] || "" }
      cmd = pbShowCommandsWithHelp(msgwin, names, helps, -1, 0)
      pbDisposeMessageWindow(msgwin)
      return cmd < 0 ? nil : rows[cmd][2]
    end

    def safely(what)
      yield
    rescue => e
      pbMessage(_INTL("{1} didn't work: {2}", what, e.message))
      KIF.log("Cody Debug: #{what} failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    end

    def open
      return unless enabled?
      loop do
        rows = [
          [_INTL("Warp"), _INTL("Go anywhere: any map by name, a town, a shuffled door."), :warp],
          [_INTL("Give"), _INTL("Badges, field-move tools, travel items, balls, money, any item."), :give],
          [_INTL("Party"), _INTL("Heal, set levels, add any Pokémon or fusion."), :party]
        ]
        rows << [_INTL("Entrances"), _INTL("Where this map's doors lead, level numbers here, found doors."), :entrances] if er_active?
        rows << [_INTL("Cheats ({1})", cheat_summary), _INTL("No wild encounters, trainers don't spot you, walk through walls."), :cheats]
        rows << [_INTL("Save now"), _INTL("Save the game right here."), :save]
        if defined?(KIF::AICompare)
          rows << [_INTL("AI compare log ({1})", KIF::AICompare.on? ? _INTL("on") : _INTL("off")),
                   _INTL("Every AI decision also asks the other AI (PIF / DemICE) and writes both to KIF_ai_compare.txt."), :aicompare]
        end
        rows << [_INTL("Fetch missing base sprite sheets"), _INTL("Download every base Pokémon's sprite sheet the game folder lacks (gently, one every 2 s)."), :sheets]
        pick = choose(_INTL("Cody Debug"), rows)
        break unless pick
        done = false
        safely(pick.to_s) {
          done = case pick
                 when :warp then warp_menu
                 when :give then give_menu
                 when :party then party_menu
                 when :entrances then entrances_menu
                 when :cheats then cheats_menu
                 when :save then pbMessage(Game.save ? _INTL("Saved.") : _INTL("Saving failed.")); nil
                 when :sheets then fetch_base_sheets
                 when :aicompare
                   KIF::AICompare.on = !KIF::AICompare.on?
                   pbMessage(KIF::AICompare.on? ? _INTL("AI compare log on: KIF_ai_compare.txt in the Logs folder.") : _INTL("AI compare log off.")); nil
                 end
        }
        break if done == :close
      end
    end

    #---------------------------------------------------------------------------
    # Warp
    #---------------------------------------------------------------------------
    def warp_menu
      rows = [[_INTL("By name"), _INTL("Type part of a map's name to filter the list."), :name],
              [_INTL("Town map"), _INTL("Pick a spot on the Town Map (anywhere, like Fly)."), :fly]]
      rows << [_INTL("Recent ({1})", recent_list.length), _INTL("Maps you warped to lately."), :recent] unless recent_list.empty?
      rows << [_INTL("Shuffled door"), _INTL("Stand at a shuffled door's doorstep, or inside its place."), :door] if er_active?
      case choose(_INTL("Warp"), rows)
      when :name
        list = []
        (pbMapTree rescue []).each { |m| list << [m[0], "#{m[1]} (#{m[0]})"] }
        id = pbChooseListWithFilter(list, $game_map.map_id, -1, 1, 0, 0, _INTL("Type to filter"))
        return nil if !id || id <= 0
        spot = landing_for(id)
        return warp_to(id, spot[0], spot[1])
      when :fly
        ret = pbBetterRegionMap(-1, true, true, false, nil, true)
        return nil unless ret
        return warp_to(ret[0], ret[1], ret[2])
      when :recent
        id = choose(_INTL("Recent"), recent_list.map { |r| [r[3], nil, r] })
        return id ? warp_to(id[0], id[1], id[2]) : nil
      when :door
        return door_warp_menu
      end
      return nil
    end

    def recent_list
      return KIF::CodyDebug.recent
    end

    # Where to stand on a map: where some door or path leads in, else a free tile
    def landing_for(map_id)
      @landings ||= {}
      return @landings[map_id] if @landings[map_id]
      d = er_dat
      if d
        d[:doors].each do |o|
          return (@landings[map_id] = [o[:to][1], o[:to][2]]) if o[:to][0] == map_id
          return (@landings[map_id] = [o[:exit_to][1], o[:exit_to][2]]) if o[:exit_to] && o[:exit_to][0] == map_id
        end
      end
      map = Game_Map.new
      map.setup(map_id)
      cx = map.width / 2; cy = map.height / 2
      best = nil
      (0..[map.width, map.height].max).each do |r|
        (-r..r).each do |dx|
          (-r..r).each do |dy|
            next unless dx.abs == r || dy.abs == r
            x = cx + dx; y = cy + dy
            next unless map.valid?(x, y) && map.passableStrict?(x, y, 0, $game_player)
            next if map.events.values.any? { |ev| ev.at_coordinate?(x, y) && !ev.through && ev.character_name != "" }
            best = [x, y]; break
          end
          break if best
        end
        break if best
      end
      return (@landings[map_id] = best || [cx, cy])
    end

    def warp_to(map_id, x, y, dir = 2)
      name = (pbGetMapNameFromId(map_id) rescue map_id.to_s)
      KIF::CodyDebug.recent.reject! { |r| r[0] == map_id }
      KIF::CodyDebug.recent.unshift([map_id, x, y, "#{name} (#{map_id})"])
      KIF::CodyDebug.recent.pop while KIF::CodyDebug.recent.length > RECENT_MAX
      if $scene.is_a?(Scene_Map)
        $game_temp.player_new_map_id    = map_id
        $game_temp.player_new_x         = x
        $game_temp.player_new_y         = y
        $game_temp.player_new_direction = dir
        pbCancelVehicles rescue nil
        $scene.transfer_player
        $game_map.refresh
      end
      return :close
    end

    #---------------------------------------------------------------------------
    # Give
    #---------------------------------------------------------------------------
    PACKS = {
      starter:  [[:POKEBALL, 20], [:GREATBALL, 10], [:POTION, 10], [:SUPERPOTION, 5], [:REVIVE, 5],
                 [:ANTIDOTE, 5], [:PARLYZHEAL, 5], [:ESCAPEROPE, 3], [:REPEL, 10], [:TOWNMAP, 1]],
      tools:    [[:MACHETE, 1], [:SURFBOARD, 1], [:LEVER, 1], [:PICKAXE, 1], [:CLIMBINGGEAR, 1],
                 [:SCUBAGEAR, 1], [:JETPACK, 1]],
      travel:   [[:BICYCLE, 1], [:TELEPORTER, 1], [:MANSIONKEY, 1], [:TOWNMAP, 1], [:OLDROD, 1],
                 [:GOODROD, 1], [:SUPERROD, 1]],
      balls:    [[:POKEBALL, 50], [:GREATBALL, 30], [:ULTRABALL, 30], [:MASTERBALL, 3]],
      medicine: [[:FULLRESTORE, 20], [:MAXREVIVE, 10], [:MAXELIXIR, 10], [:RARECANDY, 50], [:MAXREPEL, 20]]
    }

    def give_menu
      rows = [[_INTL("Starter kit"), _INTL("Pokédex, Town Map, balls, potions, repels."), :starter],
              [_INTL("Badges"), _INTL("The 8 Kanto badges, or all 16."), :badges],
              [_INTL("Field-move tools"), _INTL("Machete, Surfboard, Lever, Pickaxe, Climbing Gear, Scuba Gear, Jetpack."), :tools],
              [_INTL("Travel"), _INTL("Bicycle, Teleporter, Seagallop Pass, rods, Town Map."), :travel],
              [_INTL("Lots of balls"), _INTL("Poké, Great, Ultra and Master Balls."), :balls],
              [_INTL("Medicine"), _INTL("Full Restores, Max Revives, Max Elixirs, Rare Candies, Max Repels."), :medicine],
              [_INTL("Money"), _INTL("Add $100,000."), :money],
              [_INTL("Any item"), _INTL("Type part of an item's name."), :item]]
      pick = choose(_INTL("Give"), rows)
      case pick
      when nil then return nil
      when :starter
        $Trainer.has_pokedex = true
        $Trainer.pokedex.unlock(-1) rescue nil
        give_pack(PACKS[:starter], _INTL("Starter kit"))
      when :badges
        n = choose(_INTL("Badges"), [[_INTL("8 (Kanto)"), nil, 8], [_INTL("16 (Kanto + Johto)"), nil, 16]])
        return nil unless n
        n.times { |i| $Trainer.badges[i] = true }
        pbMessage(_INTL("You have {1} badges.", $Trainer.badge_count))
      when :money
        $Trainer.money += 100_000
        pbMessage(_INTL("Money: ${1}", $Trainer.money.to_s_formatted)) rescue pbMessage(_INTL("Money added."))
      when :item
        list = []
        GameData::Item.each { |i| list << [i.id_number, i.name, i.id] }
        id = pbChooseListWithFilter(list, nil, nil, 1, 0, 0, _INTL("Type to filter"))
        return nil unless id
        params = ChooseNumberParams.new
        params.setRange(1, 999); params.setDefaultValue(1)
        qty = pbMessageChooseNumber(_INTL("How many {1}?", GameData::Item.get(id).name), params)
        give_pack([[id, qty]], GameData::Item.get(id).name)
      else
        give_pack(PACKS[pick], rows.find { |r| r[2] == pick }[0])
      end
      return nil
    end

    def give_pack(list, title)
      got = []
      list.each do |id, qty|
        next unless GameData::Item.exists?(id)
        next if GameData::Item.get(id).is_key_item? && $PokemonBag.pbHasItem?(id)
        got << "#{GameData::Item.get(id).name} x#{qty}" if $PokemonBag.pbStoreItem(id, qty)
      end
      pbMessage(got.empty? ? _INTL("{1}: nothing new.", title) : _INTL("{1}: {2}.", title, got.join(", ")))
    end

    #---------------------------------------------------------------------------
    # Party
    #---------------------------------------------------------------------------
    def party_menu
      rows = [[_INTL("Heal"), _INTL("Full HP, PP and status for the whole party."), :heal],
              [_INTL("Set level"), _INTL("Pick a party Pokémon and a level."), :level],
              [_INTL("Add Pokémon"), _INTL("Any species by name, at any level."), :add],
              [_INTL("Add fusion"), _INTL("Pick a head and a body."), :fusion],
              [_INTL("Max IVs"), _INTL("Perfect IVs for the whole party."), :ivs]]
      case choose(_INTL("Party"), rows)
      when :heal
        $Trainer.heal_party
        pbMessage(_INTL("Party healed."))
      when :level
        pk = pick_party
        return nil unless pk
        lv = ask_level(pk.level)
        pk.level = lv; pk.calc_stats
        pbMessage(_INTL("{1} is now level {2}.", pk.name, lv))
      when :add
        sp = pick_species(_INTL("Species"))
        return nil unless sp
        add_pokemon(sp, ask_level(10))
      when :fusion
        head = pick_species(_INTL("Head"))
        return nil unless head
        body = pick_species(_INTL("Body"))
        return nil unless body
        add_pokemon(fusionOf(head, body), ask_level(10))
      when :ivs
        $Trainer.party.each { |pk| GameData::Stat.each_main { |s| pk.iv[s.id] = 31 }; pk.calc_stats }
        pbMessage(_INTL("Party IVs maxed."))
      end
      return nil
    end

    def pick_party
      return nil if $Trainer.party.empty?
      return choose(_INTL("Which?"), $Trainer.party.map { |pk| ["#{pk.name} Lv.#{pk.level}", nil, pk] })
    end

    def pick_species(title)
      list = []
      GameData::Species.each do |s|
        next if s.form != 0 || s.id_number > Settings::NB_POKEMON
        list << [s.id_number, s.real_name, s.id]
      end
      return pbChooseListWithFilter(list, nil, nil, 1, 0, 0, _INTL("{1}: type to filter", title))
    end

    def ask_level(default)
      params = ChooseNumberParams.new
      params.setRange(1, GameData::GrowthRate.max_level)
      params.setDefaultValue(default)
      return pbMessageChooseNumber(_INTL("Level?"), params)
    end

    def add_pokemon(species, level)
      pk = Pokemon.new(species, level)
      if $Trainer.party_full?
        pbStorePokemon(pk)
      else
        $Trainer.party << pk
      end
      $Trainer.pokedex.register(pk) rescue nil
      pbMessage(_INTL("{1} (Lv.{2}) added.", pk.name, level))
    end

    #---------------------------------------------------------------------------
    # Entrances
    #---------------------------------------------------------------------------
    def er
      return KIF::Rand::ER if defined?(KIF::Rand::ER)
      return nil
    end

    def er_active?
      return er && er.active? ? true : false
    rescue
      return false
    end

    def er_dat
      return er ? er.dat : nil
    rescue
      return nil
    end

    def entrances_menu
      rows = [[_INTL("Doors on this map"), _INTL("Where each shuffled door here leads; pick one to go through."), :here],
              [_INTL("Levels here"), _INTL("How far into the game this map is, its level cap and factor."), :levels],
              [_INTL("Mark all doors found"), _INTL("Fill the Entrance log (for testing the map)."), :all],
              [_INTL("Forget found doors"), _INTL("Empty the Entrance log."), :forget]]
      case choose(_INTL("Entrances"), rows)
      when :here then return doors_here
      when :levels
        m = $game_map.map_id
        s = er.state
        bin = (er.layout_progress[m] rescue nil)
        lines = [_INTL("{1} ({2})", (pbGetMapNameFromId(m) rescue m), m),
                 _INTL("Progress: {1} of {2} (vanilla {3})", bin.inspect, er::PROGRESS_BINS, er.dat[:map_progress][m].inspect),
                 _INTL("Doors from the start: {1}", (s[:near] || {})[m].inspect),
                 _INTL("Level factor x{1}; cap {2}; trainer cap {3}", er.level_factor(m).round(2), er.level_cap(m).inspect, er.trainer_cap(m).inspect)]
        pbMessage(lines.join("\n"))
      when :all
        s = er.state
        s[:seen] ||= []
        s[:in].each_key { |id| s[:seen] << [id, :in] unless s[:seen].include?([id, :in]) }
        pbMessage(_INTL("All {1} doors marked found.", s[:in].length))
      when :forget
        er.state[:seen] = []
        pbMessage(_INTL("Entrance log emptied."))
      end
      return nil
    end

    # This map's shuffled doors; going through one uses the real redirect
    def doors_here
      d = er.dat; s = er.state
      m = $game_map.map_id
      rows = []
      d[:doors].each do |o|
        next unless o[:map] == m && s[:in].key?(o[:id])
        i = d[:door_by_id][s[:in][o[:id]]]
        rows << ["#{o[:label]} -> #{er.door_name(i)}", nil, [:in, o, i]]
      end
      d[:doors].each do |o|
        next unless o[:exit_map] == m && s[:out].key?(o[:id])
        b = d[:door_by_id][s[:out][o[:id]]]
        rows << [_INTL("Way out -> {1}", er.door_name(b)), nil, [:out, o, b]]
      end
      if rows.empty?
        pbMessage(_INTL("No shuffled doors on this map."))
        return nil
      end
      pick = choose(_INTL("Doors here"), rows)
      return nil unless pick
      kind, o, t = pick
      er.note(o[:id], kind)
      if kind == :in
        return warp_to(t[:to][0], t[:to][1], t[:to][2], t[:to_dir] || 2)
      end
      return warp_to(t[:exit_to][0], t[:exit_to][1], t[:exit_to][2], t[:exit_dir] || 2)
    end

    def door_warp_menu
      d = er.dat; s = er.state
      list = []
      d[:doors].each do |o|
        next unless s[:in].key?(o[:id])
        list << [o[:id], "#{er.door_name(o)}", o[:id]]
      end
      id = pbChooseListWithFilter(list, nil, nil, 1, 0, 0, _INTL("Type to filter doors"))
      return nil unless id
      o = d[:door_by_id][id]
      side = choose(er.door_name(o), [[_INTL("Its doorstep"), _INTL("Outside, in front of the door."), :step],
                                        [_INTL("Where it leads"), _INTL("Inside the place this door now leads into."), :in]])
      return nil unless side
      if side == :step
        return warp_to(o[:exit_to][0], o[:exit_to][1], o[:exit_to][2], o[:exit_dir] || 2)
      end
      er.note(o[:id], :in)
      t = d[:door_by_id][s[:in][o[:id]]]
      return warp_to(t[:to][0], t[:to][1], t[:to][2], t[:to_dir] || 2)
    end

    #---------------------------------------------------------------------------
    # Base sprite sheets: the ones not in the game folder, from PIF's server
    # (for shipping a complete set; a gentle pace, nothing like the game's
    # own burst limit)
    #---------------------------------------------------------------------------
    def fetch_base_sheets
      dir = BaseSpriteExtracter::SPRITESHEET_FOLDER_PATH
      url = Settings::BASE_POKEMON_SPRITESHEET_TRUE_SIZE_URL.to_s
      if url.empty?
        pbMessage(_INTL("No download address yet: turn Download data on and restart once."))
        return nil
      end
      missing = (1..Settings::NB_POKEMON).reject { |n| File.file?("#{dir}#{n}.png") }
      if missing.empty?
        pbMessage(_INTL("All {1} base sprite sheets are already in the game folder.", Settings::NB_POKEMON))
        return nil
      end
      return nil unless pbConfirmMessage(_INTL("{1} base sprite sheets are missing. Download them now (about {2} minutes)?", missing.length, (missing.length * 2 / 60.0).ceil))
      ensure_folder_exists(dir)
      got = 0; failed = []
      missing.each_with_index do |n, i|
        KIF::Rand.progress(_INTL("Sheet {1} ({2}/{3})...", n, i + 1, missing.length), i.to_f / missing.length) if defined?(KIF::Rand) && KIF::Rand.respond_to?(:progress)
        ok = fetch_sprite_from_web("#{url}#{n}.png", "#{dir}#{n}.png") rescue false
        ok ? got += 1 : failed << n
        break if failed.length >= 10 && got == 0   # the server isn't answering
        t = Time.now
        while Time.now - t < 2.0
          Graphics.update; Input.update
        end
      end
      KIF::Rand.progress_done if defined?(KIF::Rand) && KIF::Rand.respond_to?(:progress_done)
      msg = _INTL("Downloaded {1} sheets.", got)
      msg += " " + _INTL("Not found (no sheet exists for them): {1}.", failed.join(", ")) unless failed.empty?
      pbMessage(msg)
      KIF.log("Base sprite sheets: #{got} downloaded, missing on the server: #{failed.inspect}")
      return nil
    end

    #---------------------------------------------------------------------------
    # Cheats
    #---------------------------------------------------------------------------
    def cheat_summary
      on = []
      on << _INTL("no wild") if KIF::CodyDebug.no_encounters
      on << _INTL("unseen") if KIF::CodyDebug.no_sight
      on << _INTL("ghost") if KIF::CodyDebug.ghost
      return on.empty? ? _INTL("off") : on.join(", ")
    end

    def cheats_menu
      loop do
        f = ->(v) { v ? _INTL("On") : _INTL("Off") }
        rows = [[_INTL("No wild encounters: {1}", f.call(KIF::CodyDebug.no_encounters)), _INTL("Grass, caves and water stay quiet."), :enc],
                [_INTL("Trainers don't spot you: {1}", f.call(KIF::CodyDebug.no_sight)), _INTL("You can still talk to them to battle."), :sight],
                [_INTL("Walk through walls: {1}", f.call(KIF::CodyDebug.ghost)), _INTL("Same as holding Ctrl in debug mode."), :ghost]]
        case choose(_INTL("Cheats"), rows)
        when :enc then KIF::CodyDebug.no_encounters = !KIF::CodyDebug.no_encounters
        when :sight then KIF::CodyDebug.no_sight = !KIF::CodyDebug.no_sight
        when :ghost then KIF::CodyDebug.ghost = !KIF::CodyDebug.ghost
        else break
        end
      end
      return nil
    end
  end
end

#-------------------------------------------------------------------------------
# Hooks (each only does something in debug mode)
#-------------------------------------------------------------------------------
class Scene_Map
  alias kif_cdbg_update update unless method_defined?(:kif_cdbg_update)

  def update
    kif_cdbg_update
    begin
      return unless $DEBUG && $scene == self
      return if $game_temp.message_window_showing || $game_player.moving? || pbMapInterpreterRunning?
      return unless (Input.triggerex?(KIF::CodyDebug::KEY) rescue false)
      KIF::CodyDebug.open
    rescue => e
      KIF.log("Cody Debug failed to open (#{e.class}: #{e.message})") if defined?(KIF.log)
    end
  end
end

class PokemonEncounters
  alias kif_cdbg_encounter_possible_here? encounter_possible_here? unless method_defined?(:kif_cdbg_encounter_possible_here?)

  def encounter_possible_here?
    return false if $DEBUG && KIF::CodyDebug.no_encounters
    return kif_cdbg_encounter_possible_here?
  end
end

alias kif_cdbg_pbEventCanReachPlayer? pbEventCanReachPlayer? unless defined?(kif_cdbg_pbEventCanReachPlayer?)
def pbEventCanReachPlayer?(event, player, distance)
  return false if $DEBUG && KIF::CodyDebug.no_sight && distance > 1 && event.respond_to?(:name) && event.name.to_s[/trainer/i]
  return kif_cdbg_pbEventCanReachPlayer?(event, player, distance)
end

class Game_Player
  alias kif_cdbg_passable? passable? unless method_defined?(:kif_cdbg_passable?)

  def passable?(x, y, d, strict = false)
    return true if $DEBUG && KIF::CodyDebug.ghost && $game_map.valid?(x + (d == 6 ? 1 : d == 4 ? -1 : 0), y + (d == 2 ? 1 : d == 8 ? -1 : 0))
    return kif_cdbg_passable?(x, y, d, strict)
  end
end
