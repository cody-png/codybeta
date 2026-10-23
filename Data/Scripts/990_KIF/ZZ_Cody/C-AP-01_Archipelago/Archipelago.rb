#===============================================================================
# C-AP-01 – Archipelago, phase 2 (Kanto) (2026-10-22)
#   Talks to the KIF Client (in the kif.apworld) through files in
#   <game folder>/Archipelago/ (the engine has no sockets):
#     slot.json        client -> game: seed, slot name, player, location ids,
#                      map copies (aliases), gym badge events, badges for the
#                      League, DeathLink (written when the client connects)
#     scouts.json      client -> game: what each location holds (item, player)
#     in/items.json    client -> game: every item received so far, with index
#     in/death.json    client -> game: last DeathLink received (time, source)
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
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :kif_ap
end

module KIF
  module AP
    FOLDER = "Archipelago"
    POLL_FRAMES = 60
    BADGE_BASE = 9_000_000
    BADGE_SET_RE = /\$Trainer\.badges\[(\d+)\]\s*=\s*true/
    LEAGUE_MAP = 148          # Pokemon League entrance: the 8-badge guards
    LEAGUE_RE = /numbadges\s*>=\s*8/
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

    def read_slot
      h = KIF::Mods.read_json(path("slot.json"))
      return nil unless h && !h["seed"].to_s.empty? && h["locations"].is_a?(Array)
      return h
    rescue StandardError
      return nil
    end

    def link!(slot)
      aliases = {}
      (slot["aliases"] || {}).each { |k, v| aliases[k.to_i] = v.to_i }
      $PokemonGlobal.kif_ap = {
        seed: slot["seed"].to_s, slot: slot["slot"].to_s, player: slot["player"].to_i,
        locations: slot["locations"].map(&:to_i), death_link: slot["death_link"] ? true : false,
        aliases: aliases, badge_events: (slot["badge_events"] || []).map { |e| e.map(&:to_i) },
        league_badges: (slot["league_badges"] || 8).to_i,
        received: 0, checked: [], goal: false, dirty: false, death_time: Time.now.to_f
      }
      # assumed decision: start with the DNA Splicers
      $PokemonBag.pbStoreItem(:DNASPLICERS, 1) if $PokemonBag && !$PokemonBag.pbHasItem?(:DNASPLICERS)
      reset_cache
      KIF.log("Archipelago: save linked to #{slot['slot']} (seed #{slot['seed']}, #{slot['locations'].length} locations)")
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
    def location_of(map_id, event_id)
      return nil unless on? && event_id.to_i > 0
      d = data
      id = map_id.to_i * 1000 + event_id.to_i
      id = (d[:aliases] || {})[id] || id
      return nil unless d[:locations].include?(id) && !d[:checked].include?(id)
      return id
    end

    # ... of the event running now
    def location_here
      return nil unless on? && $game_map
      ev = (pbMapInterpreter.instance_variable_get(:@event_id) rescue 0).to_i
      return location_of($game_map.map_id, ev)
    end

    def check!(id)
      d = data
      d[:checked] << id unless d[:checked].include?(id)
      KIF.verbose("Archipelago: checked #{id}")
      write_out
    end

    # What a location holds, from scouts.json: {"item", "player", "own"} or nil
    def scout(id)
      f = path("scouts.json")
      mt = (File.mtime(f) rescue nil)
      if mt && mt != @scouts_mtime
        @scouts_mtime = mt
        h = KIF::Mods.read_json(f)
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
    rescue StandardError => e
      d[:dirty] = true if d   # retried at the next poll
      KIF.log("Archipelago: couldn't write a check (#{e.class}: #{e.message})")
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
      h = KIF::Mods.read_json(f)
      return unless h
      if h["seed"].to_s != d[:seed]
        KIF.log("Archipelago: items.json is for seed #{h['seed']}, this save is linked to #{d[:seed]}; ignored")
        return
      end
      list = (h["items"] || []).select { |e| e.is_a?(Hash) && e["index"].to_i >= d[:received] }
      @queue = list.sort_by { |e| e["index"].to_i }
    end

    def poll_death(d)
      return unless d[:death_link]
      f = path("in", "death.json")
      mt = (File.mtime(f) rescue nil)
      return if mt.nil? || mt == @death_mtime
      @death_mtime = mt
      h = KIF::Mods.read_json(f)
      @death = h if h && h["time"].to_f > d[:death_time].to_f
    end

    def received_text(name, who, d)
      return _INTL("You got {1}!", name) if who.empty? || who == d[:slot]
      return _INTL("Received {1} from {2}!", name, who)
    end

    # One received item; false = can't take it now (bag pocket full)
    def grant(e, d)
      who = e["from"].to_s
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
      grant_death(d) if @death
    end

    def grant_death(d)
      h = @death
      @death = nil
      d[:death_time] = h["time"].to_f
      pbMessage(_INTL("{1} fainted, and so does your team...", h["source"].to_s.empty? ? _INTL("Someone") : h["source"].to_s))
      @dying = true
      begin
        $Trainer.party.each { |pk| pk.hp = 0 }
        pbStartOver
      ensure
        @dying = false
      end
    end

    # The map and the player are idle: nothing would be cut off by a message
    def busy_reason
      return "not on the map" unless $scene.is_a?(Scene_Map)
      return "a message or menu is open" if $game_temp.message_window_showing || $game_temp.in_menu
      return "an event is running (map #{$game_map.map_id}, event #{pbMapInterpreter.get_self.id rescue '?'})" if pbMapInterpreterRunning?
      return "the player is moving"
    rescue StandardError
      return "unknown"
    end

    def quiet?
      return false unless $scene.is_a?(Scene_Map)
      return false if $game_temp.message_window_showing || $game_temp.in_menu
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
      end
      @timer += 1
      return if @timer < POLL_FRAMES
      @timer = 0
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
        poll
        n = @queue.count { |e| e["index"].to_i >= d[:received] }
        pbMessage(_INTL("{1} items waiting. They arrive once you can walk around freely (no message, menu or event running).", n)) if n > 0
        return
      end
      unless slot
        pbMessage(_INTL("No Archipelago game found. Start the KIF Client and connect first."))
        return
      end
      q = on? ? _INTL("This save is linked to another Archipelago game. Link it to {1} instead?", slot["slot"]) :
                _INTL("Link this save to Archipelago as {1}?", slot["slot"])
      return unless pbConfirmMessage(q)
      link!(slot)
      pbMessage(_INTL("Linked. Keep the KIF Client running to send checks and get items."))
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
  KIF::AP.goal! if KIF::AP.on?
  return kif_ap_pbHallOfFameEntry(*args)
end

def pbStartOver(*args)
  KIF::AP.death_out if KIF::AP.on?
  return kif_ap_pbStartOver(*args)
end

class Interpreter
  alias kif_ap_execute_script execute_script unless method_defined?(:kif_ap_execute_script)

  # Gym badges and the League guards' badge count (only for a linked save)
  def execute_script(script)
    script = KIF::AP.rewrite_script(script, @map_id, @event_id) if script.is_a?(String) && KIF::AP.on?
    return kif_ap_execute_script(script)
  end
end
