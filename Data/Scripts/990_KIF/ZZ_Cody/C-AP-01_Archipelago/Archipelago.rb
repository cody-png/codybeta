#===============================================================================
# C-AP-01 – Archipelago, phase 1 (spike) (2026-10-22)
#   Talks to the KIF Client (in the kif.apworld) through files in
#   <game folder>/Archipelago/ (the engine has no sockets):
#     slot.json        client -> game: seed, slot name, player, location ids,
#                      DeathLink (written when the client connects)
#     in/items.json    client -> game: every item received so far, with index
#     in/death.json    client -> game: last DeathLink received (time, source)
#     out/<n>.json     game -> client: seed, all checked location ids, goal,
#                      death (the client sends them and deletes the file)
#   Both sides write a temp file and rename it.
#   A save is in AP mode only after "Archipelago" in the pause menu links it
#   (the entry shows once slot.json exists). The link, received index and
#   checked locations live in the save ($PokemonGlobal.kif_ap).
#   Location id = map id * 1000 + event id. An item ball / gift whose event
#   is one of the slot's locations sends a check instead of giving its item.
#   Received items are given on the map at a quiet moment (no message, menu
#   or event), checked every 60 frames and right after a save is loaded.
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :kif_ap
end

module KIF
  module AP
    FOLDER = "Archipelago"
    POLL_FRAMES = 60
    @timer = 0
    @global = nil
    @mtime = nil
    @death_mtime = nil
    @queue = []
    @death = nil
    @seq = 0
    @dying = false

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
      $PokemonGlobal.kif_ap = {
        seed: slot["seed"].to_s, slot: slot["slot"].to_s, player: slot["player"].to_i,
        locations: slot["locations"].map(&:to_i), death_link: slot["death_link"] ? true : false,
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
    end

    #---------------------------------------------------------------------------
    # Checks (game -> client)
    #---------------------------------------------------------------------------
    # The AP location of the event running now, if it is one of the slot's
    def location_here
      return nil unless on? && $game_map
      ev = (pbMapInterpreter.instance_variable_get(:@event_id) rescue 0).to_i
      return nil if ev <= 0
      id = $game_map.map_id * 1000 + ev
      return data[:locations].include?(id) ? id : nil
    end

    def check!(id)
      d = data
      d[:checked] << id unless d[:checked].include?(id)
      KIF.verbose("Archipelago: checked #{id}")
      write_out
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

    def grant_pending
      return unless on?
      d = data
      while (e = @queue.first)
        idx = e["index"].to_i
        if idx >= d[:received]
          it = (GameData::Item.try_get(e["item"].to_s.to_sym) rescue nil)
          if it
            break unless $PokemonBag.pbStoreItem(it, [e["count"].to_i, 1].max)   # bag full: try again later
            who = e["from"].to_s
            if who.empty? || who == d[:slot]
              pbMessage(_INTL("\\me[Item get]You got {1}!\\wtnp[30]", it.name))
            else
              pbMessage(_INTL("\\me[Item get]Received {1} from {2}!\\wtnp[30]", it.name, who))
            end
          else
            KIF.log("Archipelago: unknown item #{e['item'].inspect} (index #{idx}) skipped")
          end
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
      return if @timer < POLL_FRAMES || !quiet?
      @timer = 0
      poll
      grant_pending
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

def pbItemBall(*args)
  id = KIF::AP.location_here
  return kif_ap_pbItemBall(*args) unless id
  KIF::AP.check!(id)
  pbMessage(_INTL("\\me[Item get]You found an Archipelago item!\\wtnp[30]"))
  return true
end

def pbReceiveItem(*args)
  id = KIF::AP.location_here
  return kif_ap_pbReceiveItem(*args) unless id
  KIF::AP.check!(id)
  pbMessage(_INTL("\\me[Item get]You obtained an Archipelago item!\\wtnp[30]"))
  return true
end

def pbHallOfFameEntry(*args)
  KIF::AP.goal! if KIF::AP.on?
  return kif_ap_pbHallOfFameEntry(*args)
end

def pbStartOver(*args)
  KIF::AP.death_out if KIF::AP.on?
  return kif_ap_pbStartOver(*args)
end
