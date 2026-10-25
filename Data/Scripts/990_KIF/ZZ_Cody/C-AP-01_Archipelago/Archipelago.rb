#===============================================================================
# C-AP-01 – Archipelago, phase 2 (Kanto) (2026-10-22)
#   Talks to the KIF Client (in the kif.apworld) through files in
#   <game folder>/Archipelago/ (the engine has no sockets):
#     slot.json        client -> game: seed, slot name, player, location ids,
#                      map copies (aliases), gym badge events, badges for the
#                      League, DeathLink (written when the client connects)
#     scouts.json      client -> game: what each location holds (item, player)
#     in/items.json    client -> game: every item received so far, with index
#     in/death.json    client -> game: last DeathLink received (seed, time, source)
#     out/<n>.json     game -> client: seed, all checked location ids, goal,
#                      death (the client sends them and deletes the file)
#   Both sides write a temp file and rename it.
#   A save is in AP mode only after "Archipelago" in the pause menu links it
#   (the entry shows once slot.json exists). The link, received index and
#   checked locations live in the save ($PokemonGlobal.kif_ap).
#   Locations:
#     * item balls / gifts: id = map id * 1000 + event id (a copy of a map,
#       e.g. a variant of a lab, uses the id of its original: aliases). The
#       first time the event gives its item it sends the check instead; the
#       rest of the event runs as normal, so its story switches are set.
#       Later calls (a second item, a respawning find) are vanilla.
#     * gym badges: id = BADGE_BASE + badge index. The gym leader's script
#       "$Trainer.badges[n]=true" sends the check; the badge itself comes
#       from Archipelago. "Leader beaten" switches (4-11) stay with the
#       leader's event: they gate the leader's own pages.
#   Received items are given on the map at a quiet moment (no message, menu
#   or event), checked every 60 frames and right after a save is loaded.
#   "BADGE_<n>" sets the badge (badge count, field moves, level caps).
#   Randomizer: slot.json carries the slot's KIF randomizer settings, seed
#   and difficulty; linking sets them and randomizes, so every save linked to
#   the slot gets the same world. Entrances and the found/given item
#   randomizer stay off for a linked save (FORCED; C-RAND-01 018).
#   Trainersanity (2026-10-23): id = TRAINER_BASE + map id * 1000 + event id;
#   beating that trainer (pbTrainerBattle returns true) sends the check, and
#   the partner of a double battle started by two trainers' sight too.
#   Game options (slot.json "options", kept in the save): exp_modifier (%),
#   min_catch_rate, guaranteed_catch, hm_badges_off (field moves need no
#   badges), and once when linking starting_money (-1 = keep) and free_fly
#   (an index into the Kanto towns not visited yet; -1 = off); the Party Lock
#   trap's party_lock_unlock (0 battles, 1 checks, 2 Pokemon Center),
#   party_lock_battles and party_lock_checks (Traps.rb); the Disobedience
#   Curse's curse_disobey_percent (Traps_Curse.rb). A save linked
#   by an older version has no options: everything vanilla.
#   Robustness: slot.json fields of the wrong type are dropped, a broken
#   items.json is ignored, and after a save is loaded its checks and goal are
#   written again (a client of another seed may have deleted the last file).
#   Giftsanity (2026-10-23): id = GIFT_BASE + map id * 1000 + event id;
#   the first Pokemon or egg that event hands out (pbAddPokemon, pbAddToParty,
#   pbAddPokemonSilent, pbAddForeignPokemon, pbGenerateEgg) sends the check,
#   and the player keeps the Pokemon.
#   Goals (slot.json "goal"): elite_four (the Hall of Fame, as before) or
#   gym_leaders (the 8 "leader beaten" switches 4-11 are all on).
#   The KIF Client writes in/status.json every few seconds; the pause menu
#   entry says whether it runs and is connected.
#   Regions (apworld 0.6.0): Johto's and the Sevii Islands' item balls, gifts,
#   trainers, gift Pokemon and badges are checks when the slot lists them;
#   nothing here is Kanto-only (badge_events names every shuffled badge).
#   Goal all_gym_leaders: every badge location of the slot checked (each
#   leader of the regions in play beaten). Traps ("TRAP_<kind>"): Traps.rb.
#   Dexsanity (apworld 0.7.0): Dexsanity.rb (slot "dex_milestones", "game_mode").
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :kif_ap
end

module KIF
  module AP
    FOLDER = "Archipelago"
    POLL_FRAMES = 60
    BADGE_BASE = 9_000_000
    TRAINER_BASE = 10_000_000
    GIFT_BASE = 20_000_000
    # "Leader beaten" switches, Brock to Giovanni (the gym_leaders goal)
    LEADER_SWITCHES = (4..11).to_a
    GOALS = %w[elite_four gym_leaders all_gym_leaders]
    STATUS_STALE = 30   # seconds without a status.json from the client: it isn't running
    # Kanto towns for free_fly (Pallet and Viridian are on the way anyway;
    # no Indigo Plateau: it would skip Victory Road and the League guards)
    FLY_TOWNS = [380, 1, 50, 108, 95, 19, 472, 98]
    # Game options and their value when the slot doesn't set them (vanilla)
    OPTION_DEFAULTS = { "exp_modifier" => 100, "min_catch_rate" => 3, "guaranteed_catch" => 0,
                        "hm_badges_off" => 0, "starting_money" => -1, "free_fly" => -1,
                        "party_lock_unlock" => 0, "party_lock_battles" => 3, "party_lock_checks" => 5,
                        "curse_disobey_percent" => 25 }
    BADGE_SET_RE = /\$Trainer\.badges\[(\d+)\]\s*=\s*true/
    LEAGUE_MAP = 148          # Pokemon League entrance: the 8-badge guards
    LEAGUE_RE = /numbadges\s*>=\s*8/
    # Randomizer settings fixed for a linked save: the logic needs the normal
    # doors, Archipelago places the items, and NPC requests must be doable
    FORCED = { entrances: 0, found_items: 0, given_items: 0, found_tms: 0, given_tms: 0, npc_requests: 2 }
    DIFFICULTY = { "easy" => [true, false], "normal" => [false, false], "hard" => [false, true] }
    @timer = 0
    @global = nil
    @mtime = nil
    @death_mtime = nil
    @queue = []
    @death = nil
    @seq = 0
    @dying = false
    @scouts = nil
    @scouts_mtime = nil
    @badge_note = nil

    module_function

    # Always the game folder: the KIF Client (a PC program) looks there. A
    # read-only game folder (phones) only fails to write (logged once).
    def dir; File.join(KIF::Paths.root, FOLDER); end
    def path(*parts); File.join(dir, *parts); end

    def data
      return nil unless $PokemonGlobal && $PokemonGlobal.respond_to?(:kif_ap)
      return $PokemonGlobal.kif_ap
    end

    def on?
      d = data
      return d.is_a?(Hash) && !d[:seed].to_s.empty?
    end

    # KIF's MiniJSON indexes characters, and each index into a non-ASCII string
    # costs its length: one accented Poke Ball made a big items.json take seconds to
    # read after every received item. As \uXXXX the text is ASCII and parses
    # to the same strings (a character past U+FFFF stays as it is).
    def read_json(f)
      text = File.read(f, encoding: "UTF-8").delete_prefix("\uFEFF")
      text = text.gsub(/[^\x00-\x7F]/) { |c| c.ord > 0xFFFF ? c : format("\\u%04x", c.ord) }
      h = KIF::Mods::MiniJSON.parse(text)
      return h.is_a?(Hash) ? h : nil
    rescue StandardError
      return nil
    end

    def read_slot
      h = read_json(path("slot.json"))
      return nil unless h && !h["seed"].to_s.empty? && h["locations"].is_a?(Array)
      return h
    rescue StandardError
      return nil
    end

    def forced(key)
      return on? ? FORCED[key] : nil
    end

    # A game option of the linked slot (vanilla value when unlinked or unset)
    def opt(key)
      v = on? ? (data[:options] || {})[key] : nil
      return v.nil? ? OPTION_DEFAULTS[key] : v
    end

    def int_or_nil(x)
      return x if x.is_a?(Integer)
      return x.to_i if x.is_a?(Float) || x.to_s =~ /\A-?\d+\z/
      return nil
    end

    # slot.json as the save keeps it: fields of the wrong type are dropped
    # (a hand-edited or foreign file must not break linking)
    def clean_slot(slot)
      aliases = {}
      (slot["aliases"].is_a?(Hash) ? slot["aliases"] : {}).each do |k, v|
        a = int_or_nil(k); b = int_or_nil(v)
        aliases[a] = b if a && b
      end
      events = (slot["badge_events"].is_a?(Array) ? slot["badge_events"] : []).map { |e|
        e.is_a?(Array) && e.length == 3 ? e.map { |x| int_or_nil(x) } : nil
      }.select { |e| e && !e.include?(nil) }
      options = {}
      (slot["options"].is_a?(Hash) ? slot["options"] : {}).each do |k, v|
        n = int_or_nil(v)
        options[k.to_s] = n if n && OPTION_DEFAULTS.key?(k.to_s)
      end
      milestones = (slot["dex_milestones"].is_a?(Array) ? slot["dex_milestones"] : []).map { |e|
        e.is_a?(Array) && e.length == 2 ? e.map { |x| int_or_nil(x) } : nil
      }.select { |e| e && !e.include?(nil) }
      return {
        dex_milestones: milestones, game_mode: %w[classic remix].include?(slot["game_mode"].to_s) ? slot["game_mode"].to_s : nil,
        seed: slot["seed"].to_s, slot: slot["slot"].to_s, player: int_or_nil(slot["player"]) || 0,
        locations: slot["locations"].map { |x| int_or_nil(x) }.compact, death_link: slot["death_link"] ? true : false,
        aliases: aliases, badge_events: events, league_badges: (int_or_nil(slot["league_badges"]) || 8).clamp(0, 8),
        options: options, goal_kind: GOALS.include?(slot["goal"].to_s) ? slot["goal"].to_s : "elite_four",
        received: 0, checked: [], goal: false, dirty: false, death_time: Time.now.to_f
      }
    end

    # What finishes the game (a save linked by an older version: the Hall of Fame)
    def goal_kind
      return (on? && data[:goal_kind]) || "elite_four"
    end

    # Links the save and applies the slot's settings. Returns what the link
    # turns off, or nil when applying failed (the save is left as it was).
    # turned_on gets what the slot gives the save (shown after linking)
    def link!(slot, turned_on = [])
      @link_error = nil
      turned_off = rand_turned_off
      old = $PokemonGlobal.kif_ap
      saved = KIF::Rand.capture
      saved_seed = KIF::Rand.data[:seed]
      difficulty = [$game_switches[SWITCH_GAME_DIFFICULTY_EASY], $game_switches[SWITCH_GAME_DIFFICULTY_HARD]]
      begin
        $PokemonGlobal.kif_ap = clean_slot(slot)
        reset_cache
        apply_settings(slot)   # linked already, so the forced settings hold while it runs
        why = Dex.refuse_reason($PokemonGlobal.kif_ap)
        raise(@link_error = why) if why
      rescue StandardError => e
        $PokemonGlobal.kif_ap = old
        KIF::Rand.restore(saved)
        KIF::Rand.data[:seed] = saved_seed
        $game_switches[SWITCH_GAME_DIFFICULTY_EASY], $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = difficulty
        reset_cache
        KIF.log("Archipelago: link failed, save left as it was (#{e.class}: #{e.message})")
        return nil
      end
      # assumed decision: start with the DNA Splicers
      $PokemonBag.pbStoreItem(:DNASPLICERS, 1) if $PokemonBag && !$PokemonBag.pbHasItem?(:DNASPLICERS)
      money = opt("starting_money")
      $Trainer.money = money if money >= 0
      town = free_fly_town
      turned_on << _INTL("Fly to {1}", pbGetMapNameFromId(town)) if town
      n = Dex.scan
      turned_on << (n == 1 ? _INTL("1 Pokedex check for a Pokemon the save already has") :
                             _INTL("{1} Pokedex checks for Pokemon the save already has", n)) if n > 0
      KIF.log("Archipelago: save linked to #{slot['slot']} (seed #{slot['seed']}, #{slot['locations'].length} locations, the save plays #{Dex.save_mode})")
      return turned_off
    end

    # free_fly: opens one Kanto town the save hasn't visited for Fly
    def free_fly_town
      n = opt("free_fly")
      return nil if n < 0
      towns = FLY_TOWNS.reject { |m| $PokemonGlobal.visitedMaps[m] }
      return nil if towns.empty?
      town = towns[n % towns.length]
      $PokemonGlobal.visitedMaps[town] = true
      return town
    end

    # What the save had on that a link turns off (checked before linking)
    def rand_turned_off
      r = KIF::Rand
      off = []
      off << _INTL("shuffled doors") if r.get(:entrances) > 0 || r::ER.active?
      off << _INTL("random found and given items") if [:found_items, :given_items, :found_tms, :given_tms].any? { |k| r.get(k) > 0 }
      return off
    rescue StandardError
      return []
    end

    # The slot's difficulty and randomizer: the same world for every save
    # linked to the slot. A slot without randomizer settings (older apworld)
    # leaves the save's own settings and seed. The FORCED settings and the
    # door settings are never written: the hooks (C-RAND-01 018) fix them
    # live, so an unlinked copy of the save keeps its doors and items.
    # Raises on failure (link! undoes the link).
    def apply_settings(slot)
      d = DIFFICULTY[slot["difficulty"].to_s]
      if d
        $game_switches[SWITCH_GAME_DIFFICULTY_EASY] = d[0]
        $game_switches[SWITCH_GAME_DIFFICULTY_HARD] = d[1]
      end
      r = KIF::Rand
      settings = slot["randomizer"]
      if settings.is_a?(Hash) && !settings.empty?
        keep = proc { |key| FORCED.key?(key) || key.to_s.start_with?("ent_") }
        r.code_enums.each { |key, _k, _max| r.set(key, r::DATA_DEFAULTS[key] || 0) unless keep.call(key) }   # as a built-in preset
        settings.each do |k, v|
          key = k.to_s.to_sym
          r.set(key, v.to_i) if r.setting_max(key) && !keep.call(key)
        end
      end
      return unless settings.is_a?(Hash) && !settings.empty?
      # (the Strength ranges alone randomize nothing; a randomized save is
      # randomized again, to the slot's settings). The seed changes only
      # with a Randomize now: lazily rolled parts must match the tables.
      on = settings.any? { |k, v| v.to_i != 0 && !%w[wild_bst trainer_bst].include?(k.to_s) }
      return unless on || r.available?
      seed = r.parse_seed(slot["randomizer_seed"])
      r.seed = seed if seed
      r.randomize_now
    end

    # exp_modifier (F-BATTLE-09's pbGainExpOne calls it)
    def exp_scaled(exp)
      m = opt("exp_modifier")
      return m == 100 ? exp : (exp * m / 100.0).floor
    end

    def reset_cache
      @global = $PokemonGlobal.object_id
      @mtime = nil
      @death_mtime = nil
      @queue = []
      @death = nil
      @scouts = nil
      @scouts_mtime = nil
      @badge_note = nil
    end

    #---------------------------------------------------------------------------
    # Checks (game -> client)
    #---------------------------------------------------------------------------
    # The AP location of an event (a map copy counts as its original), if it
    # is one of the slot's and not checked yet
    def location_of(map_id, event_id, base = 0)
      return nil unless on? && event_id.to_i > 0
      return nil if KIF::Rand.pinkan?(map_id.to_i)   # the quest needs its own items there
      d = data
      id = base + map_id.to_i * 1000 + event_id.to_i
      id = (d[:aliases] || {})[id] || id
      return nil unless d[:locations].include?(id) && !d[:checked].include?(id)
      return id
    end

    # ... of the event running now (the interpreter keeps the last event's id
    # after it ends: fishing, unfusing or a bag item would take its check)
    def location_here
      return nil unless on? && $game_map && pbMapInterpreterRunning?
      ev = (pbMapInterpreter.instance_variable_get(:@event_id) rescue 0).to_i
      return location_of($game_map.map_id, ev)
    end

    def check!(id)
      d = data
      unless d[:checked].include?(id)
        d[:checked] << id
        Traps.count_down("CHECKS")   # Party Lock (Traps.rb)
      end
      KIF.verbose("Archipelago: checked #{id}")
      write_out
    end

    # What a location holds, from scouts.json: {"item", "player", "own"} or nil
    def scout(id)
      f = path("scouts.json")
      mt = (File.mtime(f) rescue nil)
      if mt && mt != @scouts_mtime
        @scouts_mtime = mt
        h = read_json(f)
        @scouts = (h && h["seed"].to_s == data[:seed] && h["locations"].is_a?(Hash)) ? h["locations"] : nil
      end
      s = @scouts && @scouts[id.to_s]
      return s.is_a?(Hash) ? s : nil
    rescue StandardError
      return nil
    end

    # "You found Bob's Hookshot!" (or your own item, or an unknown one)
    def found_text(id, kind)
      s = scout(id)
      verb = kind == :given ? _INTL("obtained") : _INTL("found")
      return _INTL("You {1} an Archipelago item!", verb) unless s && !s["item"].to_s.empty?
      return _INTL("You {1} your {2}!", verb, s["item"]) if s["own"] || s["player"].to_s.empty?
      return _INTL("You {1} {2}'s {3}!", verb, s["player"], s["item"])
    end

    def found_message(id, kind)
      pbMessage(_INTL("\\me[Item get]{1}\\wtnp[30]", found_text(id, kind)))
    end

    # An item ball / gift event at a location: send the check, give nothing
    def take(kind)
      id = location_here
      return false unless id
      check!(id)
      found_message(id, kind)
      return true
    end

    # Trainersanity: a won trainer battle at a trainer location (and the
    # first trainer of a double battle two trainers started by sight)
    def trainer_won(event_ids)
      return unless on? && $game_map
      event_ids.compact.uniq.each do |ev|
        id = location_of($game_map.map_id, ev, TRAINER_BASE)
        next unless id
        check!(id)
        found_message(id, :given)
      end
    end

    # Giftsanity: a Pokemon or egg handed out at a gift location (the player
    # keeps it; only the first one the event gives counts)
    def gift_received
      return unless on? && $game_map && pbMapInterpreterRunning?   # as location_here
      ev = (pbMapInterpreter.instance_variable_get(:@event_id) rescue 0)
      id = location_of($game_map.map_id, ev, GIFT_BASE)
      return unless id
      check!(id)
      found_message(id, :given)
    end

    # gym_leaders goal: every Kanto leader beaten; all_gym_leaders: every
    # badge location of the slot checked (the leaders of every region in play)
    def check_leaders
      return unless on? && !data[:goal]
      case goal_kind
      when "gym_leaders" then goal! if LEADER_SWITCHES.all? { |s| $game_switches[s] }
      when "all_gym_leaders"
        badges = data[:locations].select { |id| id >= BADGE_BASE && id < TRAINER_BASE }
        goal! if !badges.empty? && (badges - data[:checked]).empty?
      end
    end

    # The KIF Client's last status.json: :connected, :disconnected (running,
    # no server) or :gone (not running, or another seed's client)
    def client_status
      h = read_json(path("in", "status.json"))
      return [:gone, ""] unless h.is_a?(Hash) && h["seed"].to_s == data[:seed]
      return [:gone, ""] if (Time.now.to_f - h["time"].to_f).abs > STATUS_STALE
      return [h["connected"] == true ? :connected : :disconnected, h["server"].to_s]
    rescue StandardError
      return [:gone, ""]
    end

    def client_status_text
      state, server = client_status
      case state
      when :connected then _INTL("The KIF Client is connected to {1}.", server.empty? ? _INTL("the server") : server)
      when :disconnected then _INTL("The KIF Client is running but not connected to the server.")
      else _INTL("The KIF Client isn't running or hasn't connected yet: start it to send checks and get items.")
      end
    end

    # Kanto badges are shuffled when the slot names their gym events
    def badge_shuffled?(n)
      return on? && (data[:badge_events] || []).any? { |_m, _e, b| b == n }
    end

    # Replaces "$Trainer.badges[n]=true" in event scripts (vanilla when the
    # save isn't linked or the badge isn't shuffled). At the gym's event it
    # sends the badge's check; anywhere else (a debug NPC, a script handing
    # out badges by switches) it gives nothing: badges come from Archipelago.
    def badge_set(n, map_id, event_id)
      return ($Trainer.badges[n] = true) unless badge_shuffled?(n)
      d = data
      id = BADGE_BASE + n
      at_gym = d[:badge_events].any? { |m, e, b| b == n && m == map_id && e == event_id }
      if at_gym && d[:locations].include?(id) && !d[:checked].include?(id)
        check!(id)
        @badge_note = id   # told when the script says "obtained the X Badge", or after the event
      end
      return true
    end

    # The gym's "{player} obtained the X Badge!" becomes what was found
    def badge_message?
      return false unless on? && @badge_note
      id = @badge_note
      @badge_note = nil
      found_message(id, :given)
      return true
    end

    def rewrite_script(script, map_id, event_id)
      return script unless on?
      if script =~ BADGE_SET_RE
        script = script.gsub(BADGE_SET_RE) { "KIF::AP.badge_set(#{$1.to_i}, #{map_id.to_i}, #{event_id.to_i})" }
      end
      n = data[:league_badges] || 8
      script = script.gsub(LEAGUE_RE, "numbadges>=#{n.to_i}") if map_id.to_i == LEAGUE_MAP && n != 8
      return script
    end

    def goal!
      data[:goal] = true
      KIF.log("Archipelago: goal reached")
      write_out
    end

    def death_out
      return if @dying || !data[:death_link]
      write_out("death" => true)
    end

    # Every file holds the full checked list, so a lost file is made up for
    # by the next one (the server ignores repeats).
    def write_out(extra = {})
      d = data
      KIF.mkdir_p(path("out"))
      @seq += 1
      name = format("%d_%d.json", (Time.now.to_f * 1000).to_i, @seq)
      tmp = path("out", name + ".tmp")
      body = { "seed" => d[:seed], "slot" => d[:slot], "checked" => d[:checked], "goal" => d[:goal] ? true : false }
      File.open(tmp, "wb") { |f| f.write(serialize_json(body.merge(extra))) }
      File.rename(tmp, path("out", name))
      d[:dirty] = false
      @write_failed = false
    rescue StandardError => e
      d[:dirty] = true if d   # retried at the next poll
      # logged once until a write works again (the retry comes every second)
      KIF.log("Archipelago: couldn't write a check (#{e.class}: #{e.message})") unless @write_failed
      @write_failed = true
    end

    #---------------------------------------------------------------------------
    # Items (client -> game)
    #---------------------------------------------------------------------------
    def poll
      return unless on?
      d = data
      reset_cache if @global != $PokemonGlobal.object_id   # another save was loaded
      write_out if d[:dirty]
      poll_death(d)
      f = path("in", "items.json")
      mt = (File.mtime(f) rescue nil)
      return if mt.nil? || mt == @mtime
      @mtime = mt
      h = read_json(f)
      return unless h
      if h["seed"].to_s != d[:seed]
        KIF.log("Archipelago: items.json is for seed #{h['seed']}, this save is linked to #{d[:seed]}; ignored")
        return
      end
      items = h["items"].is_a?(Array) ? h["items"] : []   # a broken file gives nothing (the client rewrites it)
      list = items.select { |e| e.is_a?(Hash) && int_or_nil(e["index"]) && e["index"].to_i >= d[:received] }
      @queue = list.sort_by { |e| e["index"].to_i }
    end

    def poll_death(d)
      return unless d[:death_link]
      f = path("in", "death.json")
      mt = (File.mtime(f) rescue nil)
      return if mt.nil? || mt == @death_mtime
      @death_mtime = mt
      h = read_json(f)
      # a death from another seed's game is not this save's (a file without a
      # seed comes from an older KIF Client)
      @death = h if h && (h["seed"].nil? || h["seed"].to_s == d[:seed]) && h["time"].to_f > d[:death_time].to_f
    end

    def received_text(name, who, d)
      return _INTL("You got {1}!", name) if who.empty? || who == d[:slot]
      return _INTL("Received {1} from {2}!", name, who)
    end

    # One received item; false = can't take it now (bag pocket full)
    def grant(e, d)
      who = e["from"].to_s
      if e["item"].to_s =~ /\ATRAP_(\w+)\z/
        Traps.add($1, who, d)   # runs at the next quiet moment (Traps.rb)
        return true
      end
      if e["item"].to_s =~ /\ABADGE_(\d+)\z/
        n = $1.to_i
        $Trainer.badges[n] = true
        name = e["name"].to_s.empty? ? _INTL("a Badge") : e["name"].to_s
        pbMessage(_INTL("\\me[Badge get]{1}\\wtnp[30]", received_text(name, who, d)))
        return true
      end
      it = (GameData::Item.try_get(e["item"].to_s.to_sym) rescue nil)
      unless it
        KIF.log("Archipelago: unknown item #{e['item'].inspect} (index #{e['index']}) skipped")
        return true
      end
      return false unless $PokemonBag.pbStoreItem(it, [e["count"].to_i, 1].max)
      pbMessage(_INTL("\\me[Item get]{1}\\wtnp[30]", received_text(it.name, who, d)))
      return true
    end

    def grant_pending
      return unless on?
      d = data
      badge_message?   # a gym event that never showed its badge message
      while (e = @queue.first)
        idx = e["index"].to_i
        if idx >= d[:received]
          break unless grant(e, d)   # bag full: try again later
          d[:received] = idx + 1
        end
        @queue.shift
      end
      Dex.tell
      Traps.tell_normal
      Traps.tell_curse_lifted
      Traps.release_locks
      Traps.run_one(d)
      grant_death(d) if @death
    end

    def grant_death(d)
      h = @death
      @death = nil
      d[:death_time] = h["time"].to_f
      pbMessage(_INTL("{1}'s team fainted, so yours does too.", h["source"].to_s.empty? ? _INTL("Someone") : h["source"].to_s))
      @dying = true
      begin
        $Trainer.party.each { |pk| pk.hp = 0 unless pk.egg? }   # an egg at 0 HP would hatch fainted
        # as after a lost battle: the fainted are dead before the whiteout
        KIF::Nuzlocke.bury_fainted if defined?(KIF::Nuzlocke) && KIF::Nuzlocke.on?
        pbStartOver
      ensure
        @dying = false
      end
    end

    # The map and the player are idle: nothing would be cut off by a message
    def busy_reason
      return "not on the map" unless $scene.is_a?(Scene_Map)
      return "a message or menu is open" if $game_temp.message_window_showing || $game_temp.in_menu
      return "a battle is starting or ending" if $game_temp.in_battle
      return "an event is running (map #{$game_map.map_id}, event #{pbMapInterpreter.get_self.id rescue '?'})" if pbMapInterpreterRunning?
      return "the player is moving"
    rescue StandardError
      return "unknown"
    end

    def quiet?
      return false unless $scene.is_a?(Scene_Map)
      return false if $game_temp.message_window_showing || $game_temp.in_menu
      # a wild battle's intro and fade-out update the map (Battle trap inside a battle)
      return false if $game_temp.in_battle
      return false if pbMapInterpreterRunning?
      return false if $game_player.moving? || $game_player.move_route_forcing
      return true
    rescue StandardError
      return false
    end

    # Each frame on the map
    def update
      return unless on?
      if @global != $PokemonGlobal.object_id
        reset_cache
        @timer = POLL_FRAMES   # just loaded: look at once
        d = data
        d[:dirty] = true if !d[:checked].empty? || d[:goal]   # send them again (see the header)
        Dex.scan   # Pokemon registered while unlinked or offline
      end
      @timer += 1
      return if @timer < POLL_FRAMES
      @timer = 0
      check_leaders
      poll   # read even when busy, so the menu can say what's waiting
      if quiet?
        @busy_since = nil
        grant_pending
      elsif !@queue.empty?
        @busy_since ||= Time.now
        if Time.now - @busy_since > 30 && !@busy_logged
          @busy_logged = true
          KIF.log("Archipelago: #{@queue.length} items waiting; not given yet because #{busy_reason}")
        end
      end
    rescue StandardError => e
      KIF.log("Archipelago: update failed (#{e.class}: #{e.message})")
    end

    #---------------------------------------------------------------------------
    # Pause menu entry
    #---------------------------------------------------------------------------
    def menu
      d = data
      slot = read_slot
      if on? && (slot.nil? || slot["seed"].to_s == d[:seed])
        pbMessage(_INTL("Archipelago: {1}. {2} checks sent, {3} items received.", d[:slot], d[:checked].length, d[:received]))
        pbMessage(client_status_text)
        poll
        n = @queue.count { |e| e["index"].to_i >= d[:received] }
        pbMessage(n == 1 ? _INTL("1 item waiting. It arrives once you can walk around freely (no message, menu or event running).") :
                           _INTL("{1} items waiting. They arrive once you can walk around freely (no message, menu or event running).", n)) if n > 0
        return
      end
      unless slot
        pbMessage(_INTL("No Archipelago game found. Start the KIF Client and connect first."))
        return
      end
      q = on? ? _INTL("This save is linked to another Archipelago game. Link it to {1} instead?", slot["slot"]) :
                _INTL("Link this save to Archipelago as {1}?", slot["slot"])
      return unless pbConfirmMessage(q)
      on = []
      off = link!(slot, on)
      unless off
        pbMessage(@link_error || _INTL("The Archipelago settings couldn't be applied, so the save was not linked. Details are in the log."))
        return
      end
      pbMessage(_INTL("Linked. Keep the KIF Client running to send checks and get items."))
      pbMessage(_INTL("This save plays {1}; the Pokedex checks follow its wild Pokemon.", Dex.mode_name(Dex.save_mode))) if Dex.slot?
      pbMessage(_INTL("Archipelago needs the normal doors and places the items itself, so these are off for this save: {1}.", off.join(", "))) unless off.empty?
      pbMessage(_INTL("This Archipelago game also gives you: {1}.", on.join(", "))) unless on.empty?
    end
  end
end

KIF::PauseMenu.add(:kif_ap, "Archipelago", order: 90,
  condition: proc { KIF::AP.on? || File.file?(KIF::AP.path("slot.json")) },
  handler: proc { |_scene|
    KIF::AP.menu
    :stay
  })

Events.onMapUpdate += proc { |_sender, _e| KIF::AP.update if $PokemonGlobal && $PokemonGlobal.kif_ap }

#-------------------------------------------------------------------------------
# Hooks
#-------------------------------------------------------------------------------
alias kif_ap_pbItemBall pbItemBall unless defined?(kif_ap_pbItemBall)
alias kif_ap_pbReceiveItem pbReceiveItem unless defined?(kif_ap_pbReceiveItem)
alias kif_ap_pbHallOfFameEntry pbHallOfFameEntry unless defined?(kif_ap_pbHallOfFameEntry)
alias kif_ap_pbStartOver pbStartOver unless defined?(kif_ap_pbStartOver)
alias kif_ap_obtainBadgeMessage obtainBadgeMessage unless defined?(kif_ap_obtainBadgeMessage)
alias kif_ap_pbTrainerBattle pbTrainerBattle unless defined?(kif_ap_pbTrainerBattle)
alias kif_ap_pbCheckHiddenMoveBadge pbCheckHiddenMoveBadge unless defined?(kif_ap_pbCheckHiddenMoveBadge)

# Trainersanity
def pbTrainerBattle(*args)
  return kif_ap_pbTrainerBattle(*args) unless KIF::AP.on?
  waiting = $PokemonTemp && $PokemonTemp.waitingTrainer
  ev = (pbMapInterpreter.instance_variable_get(:@event_id) rescue nil)
  won = kif_ap_pbTrainerBattle(*args)
  # PIF drops the waiting trainer (a single battle) when it is this same
  # trainer; it was fought only if PIF turned its self switch A on
  partner = waiting && waiting[1]
  partner = nil if partner && !$game_self_switches[[$game_map.map_id, partner, "A"]]
  KIF::AP.trainer_won([ev, partner]) if won
  return won
end

# remove_badge_requirements
def pbCheckHiddenMoveBadge(*args)
  return true if KIF::AP.opt("hm_badges_off") == 1
  return kif_ap_pbCheckHiddenMoveBadge(*args)
end

def pbItemBall(*args)
  return true if KIF::AP.take(:found)
  return kif_ap_pbItemBall(*args)
end

def pbReceiveItem(*args)
  return true if KIF::AP.take(:given)
  return kif_ap_pbReceiveItem(*args)
end

def obtainBadgeMessage(*args)
  return if KIF::AP.badge_message?
  return kif_ap_obtainBadgeMessage(*args)
end

def pbHallOfFameEntry(*args)
  KIF::AP.goal! if KIF::AP.on? && KIF::AP.goal_kind == "elite_four"
  return kif_ap_pbHallOfFameEntry(*args)
end

# Giftsanity (the Pokemon is still given; Nuzlocke's hooks of the same
# methods run inside these)
alias kif_ap_pbAddPokemon pbAddPokemon unless defined?(kif_ap_pbAddPokemon)
alias kif_ap_pbAddPokemonSilent pbAddPokemonSilent unless defined?(kif_ap_pbAddPokemonSilent)
alias kif_ap_pbAddToParty pbAddToParty unless defined?(kif_ap_pbAddToParty)
alias kif_ap_pbAddForeignPokemon pbAddForeignPokemon unless defined?(kif_ap_pbAddForeignPokemon)
alias kif_ap_pbGenerateEgg pbGenerateEgg unless defined?(kif_ap_pbGenerateEgg)

def pbAddPokemon(*args)
  ret = kif_ap_pbAddPokemon(*args)
  KIF::AP.gift_received if ret && KIF::AP.on?
  return ret
end

def pbAddPokemonSilent(*args)
  ret = kif_ap_pbAddPokemonSilent(*args)
  KIF::AP.gift_received if ret && KIF::AP.on?
  return ret
end

def pbAddToParty(*args)
  ret = kif_ap_pbAddToParty(*args)
  KIF::AP.gift_received if ret && KIF::AP.on?
  return ret
end

def pbAddForeignPokemon(*args)
  ret = kif_ap_pbAddForeignPokemon(*args)
  KIF::AP.gift_received if ret && KIF::AP.on?
  return ret
end

def pbGenerateEgg(*args)
  ret = kif_ap_pbGenerateEgg(*args)
  KIF::AP.gift_received if ret && KIF::AP.on?
  return ret
end
# PIF's own names for pbGenerateEgg (event scripts) point at the hook too
alias pbAddEgg pbGenerateEgg
alias pbGenEgg pbGenerateEgg

def pbStartOver(*args)
  KIF::AP.death_out if KIF::AP.on?
  return kif_ap_pbStartOver(*args)
end

# min_catch_rate / guaranteed_catch
module PokeBattle_BattleCommon
  alias kif_ap_pbCaptureCalc pbCaptureCalc unless method_defined?(:kif_ap_pbCaptureCalc)

  def pbCaptureCalc(pkmn, battler, catch_rate, ball)
    if KIF::AP.on?
      return 4 if KIF::AP.opt("guaranteed_catch") == 1
      catch_rate ||= pkmn.species_data.catch_rate
      catch_rate = [catch_rate, KIF::AP.opt("min_catch_rate")].max
    end
    return kif_ap_pbCaptureCalc(pkmn, battler, catch_rate, ball)
  end
end

class Interpreter
  alias kif_ap_execute_script execute_script unless method_defined?(:kif_ap_execute_script)

  # Gym badges and the League guards' badge count (only for a linked save)
  def execute_script(script)
    script = KIF::AP.rewrite_script(script, @map_id, @event_id) if script.is_a?(String) && KIF::AP.on?
    return kif_ap_execute_script(script)
  end
end
