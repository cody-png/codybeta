#===============================================================================
# F-NET-01 – Multiplayer: co-op battles, the shared part (branch kif-mp-coop;
# design: Claude Docs/Base KIF/MULTIPLAYER_PLAN.md, "Co-op battles")
#
# Two connected players who both picked "Fight together" share battles: a
# wild or trainer battle either of them starts while the other is on the same
# map and free becomes a double battle, one Pokémon out from each player's own
# party. The game that started the battle ("host" here, for that battle only)
# runs it with PIF's partner-trainer support ($PokemonGlobal.partner) and its
# AI; the partner ("guest") picks its own moves each turn over the connection
# and sees the battle from a log of what the host's battle scene did. Nothing
# runs in lockstep, so a mod or an option that differs can't make the games
# disagree: the host's game decides, the guest's only shows (NetCoopHost.rb,
# NetCoopGuest.rb).
# Inert unless Multiplayer is On, connected, and both players said yes.
#
# Messages (KIF::Net signed frames; every field is checked again here):
#   co_pact  {on}                   I want to fight together (1) / not (0)
#   co_st    {map}                  my map, when it changes
#   co_ask   {id,map,kind,max}      host: a battle starts here, join? (max: its team
#                                   size limit, from a gym's pick; 0 none)
#   co_join  {id,name,type,tid,party}  guest: yes, with this party
#   co_no    {id,why}               guest: not now
#   co_begin {id,d}                 host: trainers, parties, battlers
#   co_ev    {id,e}                 host: what its battle scene showed
#   co_cmd / co_act {id,d}          a turn: host asks, guest answers
#   co_sw / co_swr  {id,d}          a replacement: host asks, guest answers
#   co_skip  {id,d}                 host: stopped waiting for that turn or
#                                   replacement (B, time up); its AI chose
#   co_end   {id,d}                 host: result, the guest's party, Exp, catches
#   co_undo  {id,d}                 guest: forget my pick for that turn, I choose again
#   co_lock  {id,d}                 host: that turn's pick was used (too late to change)
#   co_int   {id,d}                 host: what its player picked this turn ("" not yet)
#   co_rules {r}                    the Multiplayer host: its gameplay settings (RULES)
#
# Settings: gameplay ones (RULES: shiny odds, trainer shinies, difficulty, AI,
# battle mechanics, the ball hold) are the Multiplayer host's in every shared
# battle, whichever game runs it; looks (battle UI, animations, sprites, shiny
# colour style) stay each player's own; Exp, level caps, EV/IV modes,
# Nuzlocke and Soul Link are each player's own, worked out on their own game.
#===============================================================================
KIF::Options.define(:kif_coop_hold, 1, :global)   # 0 Off, 1 On

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Co-op: hold attacks for a ball"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_coop_hold },
                 proc { |value| $PokemonSystem.kif_coop_hold = value },
                 [_INTL("Fighting together: a ball thrown at a wild Pokémon doesn't stop the partner's attack on it."),
                  _INTL("Fighting together: when one of you throws a ball at a wild Pokémon, the other's attack on it waits that turn. The host's setting counts.")])
}

KIF::Options.define(:kif_coop_second_ball, 1, :global)   # 0 Next Pokémon, 1 Back to Bag

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Co-op: second ball"), [_INTL("Next Pokémon"), _INTL("Back to Bag")],
                 proc { $PokemonSystem.kif_coop_second_ball },
                 proc { |value| $PokemonSystem.kif_coop_second_ball = value },
                 [_INTL("Fighting together: when both of you throw at one wild Pokémon and the first ball catches it, the second goes at the other wild Pokémon."),
                  _INTL("Fighting together: when both of you throw at one wild Pokémon and the first ball catches it, the second ball goes back to the Bag. The host's setting counts.")])
}

module KIF
  module Coop
    {
      "co_pact"  => { "on" => [Integer, 0, 1] },
      "co_st"    => { "map" => [Integer, 0, 99_999] },
      "co_ask"   => { "id" => [Integer, 1, 1_000_000_000], "map" => [Integer, 0, 99_999], "kind" => [String, 8],
                      "max" => [Integer, 0, 6] },
      "co_join"  => { "id" => [Integer, 1, 1_000_000_000], "name" => [String, 24], "type" => [String, 48],
                      "tid" => [Integer, 0, 0xffffffff], "party" => [Array], "items" => [Hash, :opt] },
      "co_no"    => { "id" => [Integer, 1, 1_000_000_000], "why" => [String, 16] },
      "co_begin" => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_ev"    => { "id" => [Integer, 1, 1_000_000_000], "e" => [Array] },
      "co_cmd"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_act"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_sw"    => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_swr"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_skip"  => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_end"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_undo"  => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_lock"  => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_int"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_rules" => { "r" => [Hash] },
    }.each { |k, v| KIF::Net::TYPES[k] = v }

    HOST_TYPES  = %w[co_join co_no co_act co_swr co_undo]
    GUEST_TYPES = %w[co_begin co_ev co_cmd co_sw co_skip co_end co_lock]

    # the Multiplayer host's gameplay settings: $PokemonSystem field => [min, max]
    RULES = { "shinyodds" => [1, 65_536], "shiny_trainer_pkmn" => [0, 3], "kif_coop_hold" => [0, 1], "kif_coop_second_ball" => [0, 1],
              "damage_variance" => [0, 9], "powerfulai" => [0, 9], "modernhail" => [0, 9], "frostbite" => [0, 9],
              "drowsy" => [0, 9], "bugbuff" => [0, 9], "icebuff" => [0, 9], "critical_captures" => [0, 9],
              "rocketballsteal" => [0, 9], "custom_bst_npc" => [0, 9], "cody_leader_teams" => [0, 9] }
    # difficulty: game switches, true/false
    RULE_SWITCHES = { "easy" => :SWITCH_GAME_DIFFICULTY_EASY, "hard" => :SWITCH_GAME_DIFFICULTY_HARD }

    # seconds; tests shorten them
    @ask_wait   = 3.0    # host: the partner answers a battle start
    @quiet_wait = 2.0    # guest: becomes free to join
    @begin_wait = 20.0   # guest: the host's battle shows up
    @cmd_wait   = 90.0   # host: the partner picks a move
    @sw_wait    = 60.0   # host: the partner picks a replacement
    @want = false        # I picked Fight together
    @their = false       # the partner did
    @host_box = []
    @notes = []
    @host_id = nil       # the battle this game started or is hosting: only its replies are kept (HOST_TYPES)

    # said before the player agrees: the partner's game runs the battle and tells this one what happened
    def self.trust_line
      _INTL("Their game decides what happens to your Pokemon in these battles. Only agree with a friend you trust.")
    end

    class << self
      attr_accessor :ask_wait, :quiet_wait, :begin_wait, :cmd_wait, :sw_wait
      attr_reader :host_id
      attr_accessor :guest        # the guest battle running in this game
      attr_reader :want, :their, :their_map, :host_box, :notes
    end

    def self.log(msg); KIF::Net.log("co-op: #{msg}"); end

    def self.session
      s = KIF::Net.session if KIF::Net.respond_to?(:session)
      return s&.connected? ? s : nil
    end

    # both players said yes while connected
    def self.on?
      return false unless KIF::Net.menu_on? && session
      return @want && @their ? true : false
    end

    def self.partner; session ? session.partner.to_s : "?"; end

    # this player's Auto-Battle: the host's AI picks for this player's Pokémon
    def self.auto_battle?
      return false if defined?(KIF::PvP) && KIF::PvP.running?   # nobody plays for a player in a match
      return false unless defined?(KIF::AutoBattle) && KIF::AutoBattle.on?
      return !defined?(KIF::Modules) || KIF::Modules.active?("F-BATTLE-02_AutoBattle")
    end

    def self.on_connect(_s = nil)
      @want = @their = @ask_pact = false
      @their_map = @sent_map = @ask = @rules = @rules_sent = nil
      @host_id = @pact_after = @no_asks_until = nil
      @told = {}
      @host_box.clear
    end

    # a note shown once a connection (on the map, KIF::Net.notes)
    def self.tell(key, text)
      return if (@told ||= {})[key]
      @told[key] = true
      KIF::Net.notes << text
    end

    def self.on_disconnect
      on_connect
      @guest&.lost
    end

    #---------------------------------------------------------------------------
    # Fight together: both pick it (Multiplayer screen, or yes to the partner's
    # question); either can stop it
    #---------------------------------------------------------------------------
    def self.set_want(v)
      @want = v ? true : false
      @ask_pact = false
      s = session or return
      s.post("co_pact", "on" => @want ? 1 : 0)
      send_status if @want
    end

    def self.send_status
      s = session or return
      return unless $game_map
      @sent_map = $game_map.map_id
      s.post("co_st", "map" => @sent_map)
      send_rules
    end

    #---------------------------------------------------------------------------
    # Gameplay settings: the Multiplayer host's count in every shared battle
    #---------------------------------------------------------------------------
    def self.rules_host?; (s = session) && s.respond_to?(:role) && s.role == :host ? true : false; end

    def self.my_rules
      r = {}
      RULES.each_key { |k| r[k] = $PokemonSystem.send(k).to_i if $PokemonSystem.respond_to?(k) }
      RULE_SWITCHES.each { |k, c| r[k] = ($game_switches[Object.const_get(c)] ? 1 : 0) rescue nil }
      return r
    end

    # the host sends its settings with its status, and again when they changed
    def self.send_rules
      s = session or return
      return unless rules_host? && $PokemonSystem
      r = my_rules
      return if r == @rules_sent
      @rules_sent = r
      s.post("co_rules", "r" => r)
    end

    # checked settings from the host: known names, Integers in range
    def self.read_rules(h)
      out = {}
      RULES.each { |k, (lo, hi)| out[k] = h[k] if h[k].is_a?(Integer) && h[k].between?(lo, hi) }
      RULE_SWITCHES.each_key { |k| out[k] = h[k] if h[k] == 0 || h[k] == 1 }
      return out
    end

    # a setting for this shared battle (the host's while with_rules runs)
    def self.rule(k); $PokemonSystem.respond_to?(k) ? $PokemonSystem.send(k).to_i : 0; end

    # the block runs with the Multiplayer host's gameplay settings (on the
    # joiner's game; the host's own game already has them)
    def self.with_rules
      r = @rules
      return yield if rules_host? || !r || r.empty? || !$PokemonSystem
      old = {}
      live = {}
      r.each do |k, v|
        if RULE_SWITCHES[k]
          c = Object.const_get(RULE_SWITCHES[k]) rescue next
          old[k] = $game_switches[c]
          $game_switches[c] = v == 1
          live[k] = v == 1
        elsif $PokemonSystem.respond_to?(:"#{k}=")
          old[k] = $PokemonSystem.send(k)
          $PokemonSystem.send(:"#{k}=", v)
          live[k] = v
        end
      end
      @rules_swap = [old, live]
      begin
        return yield
      ensure
        @rules_swap = nil
        put_rules(old)
      end
    end

    def self.put_rules(h)
      h.each { |k, v| RULE_SWITCHES[k] ? ($game_switches[Object.const_get(RULE_SWITCHES[k])] = v) : $PokemonSystem.send(:"#{k}=", v) }
    end

    # a save made while the host's settings are live (an autosave on a win or a catch)
    # holds this player's own settings, and the friend's team stays out of the file
    def self.saving
      g = $PokemonGlobal
      friend = g.partner if g && @hosting   # the friend's team is there for the battle only: not in the file
      g.partner = nil if friend
      sw = @rules_swap
      put_rules(sw[0]) if sw
      begin
        return yield
      ensure
        put_rules(sw[1]) if sw && @rules_swap.equal?(sw)
        g.partner = friend if friend
      end
    end

    #---------------------------------------------------------------------------
    # Shared helpers
    #---------------------------------------------------------------------------
    # the button a controller player presses, else the bound key
    def self.back_name
      return "B" if (defined?(Input::Controller) && Input::Controller.connected? rescue false)
      return KIF::Keys.name(Input::BACK)
    end

    # what a battler is about to do this turn, for the partner's screen: "Water
    # Gun -> Pidgey", "throwing a Poké Ball", "switching", "running"; nil: nothing yet
    def self.intent_text(battle, i)
      ch = battle.choices[i] or return nil
      b = battle.battlers[i]
      case ch[0]
      when :UseMove
        mv = ch[2] or return nil
        t = ch[3]
        tb = t.is_a?(Integer) && t >= 0 && t != i ? battle.battlers[t] : nil
        return tb ? _INTL("{1} -> {2}", mv.name, tb.name) : mv.name
      when :UseItem
        it = GameData::Item.try_get(ch[1]) or return nil
        return it.is_poke_ball? ? _INTL("throwing a {1}", it.name) : _INTL("using a {1}", it.name)
      when :SwitchOut then return _INTL("switching")
      when :Run then return _INTL("running")
      end
      return nil
    rescue StandardError
      return nil
    end

    # PIF's scene: the pick panel's top, over the command box and over the
    # Battle Info "INFO" tab that sits on the box's left end (it covered the text)
    INTENT_H = 26   # the pick strip, as tall as the INFO tab

    def self.intent_panel_y(h)
      tab = defined?(KIF::BattleInfo::TAB_H) ? KIF::BattleInfo::TAB_H : 0
      return Graphics.height - 96 - tab - 2 - h
    end

    # the partner's pick as a line: "Monto: Water Gun -> Pidgey", "Monto: not chosen yet"
    def self.intent_line(name, it)
      return nil if it.nil?
      t = Mon.text(it, 60).delete("\n")
      return t.empty? ? _INTL("{1}: not chosen yet", name) : _INTL("{1}: {2}", name, t)
    end

    # PIF whites out a lost battle; a player whose own Pokémon all fainted in a
    # shared battle the partner won (or got away from) blacks out the same way
    def self.black_out_check(decision, can_lose)
      return if can_lose || decision == 2 || decision == 5 || !$Trainer
      return if $Trainer.party.none? { |p| p && !p.egg? } || $Trainer.able_pokemon_count > 0
      log("every Pokémon of this player fainted in the shared battle: blacked out")
      pbCheckAllFainted
    end

    # the row on the Multiplayer connected screen
    def self.menu_label
      return _INTL("Fight together: On") if on?
      return _INTL("Fight together: {1} asked", partner) if @their && !@want
      return _INTL("Fight together: Asked") if @want
      return _INTL("Fight together: Off")
    end

    def self.menu_pick(_scr = nil)
      if @want
        return unless pbConfirmMessage(_INTL("Stop fighting together with {1}?", partner))
        set_want(false)
        note(_INTL("You stopped fighting together."))
        return
      end
      pbMessage(_INTL("Fighting together: a battle either of you starts while the other is on the same map becomes a double battle. Each of you uses your own Pokémon."))
      pbMessage(trust_line)
      return unless pbConfirmMessage(@their ? _INTL("{1} asked to fight together. OK?", partner) : _INTL("Ask {1} to fight together?", partner))
      set_want(true)
      note(on? ? _INTL("You now fight together with {1}.", partner) : _INTL("Asked {1}. They need to say yes.", partner))
    end

    # the partner asked: a question at a quiet moment on the map
    def self.ask_pact
      @ask_pact = false
      return if @want || !@their
      pbMessage(trust_line)
      yes = pbConfirmMessage(_INTL("{1} wants to fight together: battles either of you starts on the same map become double battles. OK?", partner))
      return unless session && @their
      @pact_after = KIF::Net.now + 120 unless yes   # no new question for 2 minutes
      set_want(yes)
      note(_INTL("You now fight together with {1}.", partner)) if yes
    end

    # a note for the Multiplayer screen / the map (the oldest go when nobody reads them)
    def self.note(text)
      @notes << text
      @notes.shift while @notes.length > 20
    end

    #---------------------------------------------------------------------------
    # Messages from the partner's game (KIF::Net.update)
    #---------------------------------------------------------------------------
    def self.receive(type, msg)
      case type
      when "co_pact"
        was = @their
        @their = msg["on"] == 1
        # the question comes back no sooner than 2 minutes after a No (a partner flipping this at 400 a second)
        @ask_pact = @their && !@want && KIF::Net.now >= (@pact_after || 0)
        note(_INTL("{1} stopped fighting together.", partner)) if was && !@their && @want
        note(_INTL("You now fight together with {1}.", partner)) if !was && @their && @want   # the answer to this player's ask
        send_status if @their
      when "co_st" then @their_map = msg["map"]
      when "co_rules" then @rules = read_rules(msg["r"]) unless rules_host?
      when "co_int" then @guest&.intent_from(msg)
      when "co_vs", "co_vsr" then KIF::PvP.receive(type, msg) if defined?(KIF::PvP)   # a friendly match (NetPvp.rb)
      when "co_ask" then guest_ask(msg)
      when *HOST_TYPES
        # only this game's own battle start or running battle: a stream of these piled up in memory
        if @host_id && msg["id"] == @host_id
          @host_box << [type, msg]
          @host_box.shift while @host_box.length > 32
        end
      when *GUEST_TYPES
        if @guest
          @guest.feed(type, msg)
        elsif type == "co_end" && @ask && @ask["id"] == msg["id"]
          @ask = nil   # the host gave up before this game was free
        end
      end
    end

    def self.take_notes; n = @notes.dup; @notes.clear; n; end

    # the other player's look (presence) when this battle is a co-op one, or nil
    # the partner's pick for the battle menus of this game's co-op battle, or nil
    def self.intent_for(scene)
      b = scene.instance_variable_get(:@battle) or return nil
      h = b.instance_variable_get(:@kif_coop)
      return h.partner_intent if h
      return @guest.intent if @guest && @guest.mirror.equal?(b)
      return nil
    end

    def self.partner_look(scene)
      b = scene.instance_variable_get(:@battle) or return nil
      return nil unless b.instance_variable_get(:@kif_coop) || (@guest && @guest.mirror.equal?(b))
      return defined?(KIF::Presence) ? KIF::Presence.ghost&.look : nil
    end

    #---------------------------------------------------------------------------
    # Guest: the partner's battle starts; join when this game is free
    #---------------------------------------------------------------------------
    # the states in which this game does not join a battle (the ones that stop it hosting one too)
    def self.cannot_join?
      return true if $PokemonGlobal.nil? || $PokemonGlobal.partner
      return true if (pbInSafari? rescue false) || (pbInBugContest? rescue false)
      return true if defined?(KIF::SelfBattle) && KIF::SelfBattle.instance_variable_get(:@active)
      return true if ($game_switches[SWITCH_TRIPLE_BOSS_BATTLE] rescue false)
      return false
    end

    def self.guest_ask(msg)
      s = session or return
      return KIF::PvP.got_ask(msg) if msg["kind"] == "pvp" && defined?(KIF::PvP)   # a friendly match has its own checks
      return s.post("co_no", "id" => msg["id"], "why" => "off") unless on?
      # busy, or the last invite from this partner never became a battle (5 minutes of "busy")
      return s.post("co_no", "id" => msg["id"], "why" => "busy") if @guest || @ask || @hosting || $game_temp&.in_battle ||
                                                                 cannot_join? || KIF::Net.now < (@no_asks_until || 0)
      @ask = msg
      @ask_at = KIF::Net.now
    end

    # every frame on the map
    def self.map_tick
      s = session or return
      send_status if $game_map && $game_map.map_id != @sent_map && (@want || @their)
      send_rules if @want || @their   # a setting changed on the host (sent only then)
      if @ask
        ask = @ask
        why = if !on? then "off"
              elsif ask["map"] != $game_map.map_id then "map"
              elsif cannot_join? then "busy"
              elsif ($Trainer.able_pokemon_count rescue 0) == 0 then "fainted"
              end
        if why
          @ask = nil
          return s.post("co_no", "id" => ask["id"], "why" => why)
        end
        unless KIF::Net.quiet?
          return unless KIF::Net.now - @ask_at > @quiet_wait
          @ask = nil
          return s.post("co_no", "id" => ask["id"], "why" => "busy")
        end
        @ask = nil
        return join_battle(s, ask)
      end
      ask_pact if @ask_pact && KIF::Net.quiet?
    end

    # the battle's team size limit here: a gym's pick (PokemonSelection) left this
    # many in the party; 0 none. The partner brings no more (the host's rule)
    def self.team_limit
      return @pick_max if @pick_max   # the pick's own limit (a party already that small changed nothing)
      return 0 unless $PokemonGlobal && $PokemonGlobal.pokemonSelectionOriginalParty && $Trainer
      return $Trainer.party.length.clamp(1, 6)
    rescue StandardError
      return 0
    end

    # the Pokémon a player brings: the party, or its first `max` that can fight
    # a team pick (PokemonSelection) is on until it is restored
    def self.picked(max); @pick_max = max.is_a?(Integer) && max.between?(1, 5) ? max : nil; end

    def self.join_party(trainer, max = 0)
      return trainer.party.first(6) unless max.to_i > 0
      return trainer.party.select { |p| p && p.able? }.first(max)
    end

    def self.join_data(id, trainer, max = 0, bag = nil)
      return { "id" => id, "name" => trainer.name.to_s[0, 24], "type" => trainer.trainer_type.to_s[0, 48],
               "tid" => trainer.id.to_i & 0xffffffff, "party" => join_party(trainer, max).map { |p| Mon.dump(p, true) },
               "items" => bag_list(bag || $PokemonBag) }
    end

    # the battle items this player has (name => count): the host lets it use no others
    def self.bag_list(bag)
      out = {}
      (bag ? bag.pockets : []).each do |pocket|
        next unless pocket.is_a?(Array)
        pocket.each do |it|
          next unless it.is_a?(Array) && it.length == 2 && out.length < 60
          d = GameData::Item.try_get(it[0])
          out[d.id.to_s] = [out[d.id.to_s].to_i + it[1].to_i, 999].min if d && d.battle_use.to_i.between?(1, 10)
        end
      end
      return out
    rescue StandardError
      return {}
    end

    def self.join_battle(s, ask)
      max = ask["max"].to_i
      s.post("co_join", join_data(ask["id"], $Trainer, max))
      log("joining #{partner}'s battle #{ask['id']}#{max > 0 ? " (#{max} Pokémon each)" : ''}")
      g = Guest.new(s, ask["id"], $Trainer, max: max)
      @guest = g
      begin
        g.run
      rescue StandardError, SystemStackError => e
        log("guest battle failed (#{e.class}: #{e.message})")
        (s.post("co_act", "id" => ask["id"], "d" => { "a" => "auto", "b" => -1 }) rescue nil)
      ensure
        @guest = nil
        # an invite that never became a battle: the next ones from this partner wait 5 minutes
        if g && !g.begun? && !g.done
          @no_asks_until = KIF::Net.now + 300
          tell(:ask_flood, _INTL("{1} asked you to join a battle that did not start. Their invites are ignored for 5 minutes.", partner))
        elsif g && g.stopped?   # left because the host went silent or flooded, or the player pressed B: the next invite waits too
          @no_asks_until = KIF::Net.now + 300
          tell(:ask_stopped, _INTL("You left {1}'s battle. Their invites are ignored for 5 minutes.", partner))
        end
      end
    end

    #---------------------------------------------------------------------------
    # Host: ask the partner to join a battle that is starting here.
    # A Hash (party, name, type, tid, id) or nil (fight alone)
    #---------------------------------------------------------------------------
    def self.invite(kind)
      s = session or return nil
      return nil if @their_map && $game_map && @their_map != $game_map.map_id
      @next_id = ((@next_id || (Random.rand(1000) * 1000)) + 1) % 1_000_000_000
      @next_id = 1 if @next_id == 0
      id = @next_id
      @host_box.clear
      @host_id = id
      max = team_limit
      s.post("co_ask", "id" => id, "map" => ($game_map ? $game_map.map_id : 0), "kind" => kind.to_s, "max" => max)
      reply = nil
      crossed = nil
      wait_map(@ask_wait) do
        reply = take_host(id, %w[co_join co_no])
        # both started a battle at once (crossed invites): the Multiplayer
        # host's battle is the shared one; the other game joins it first
        if !reply && @ask
          if rules_host?
            s.post("co_no", "id" => @ask["id"], "why" => "busy")
            @ask = nil
          else
            crossed = @ask
            @ask = nil
          end
        end
        reply || crossed
      end
      if crossed
        log("crossed invites: joining #{partner}'s battle #{crossed['id']} first")
        s.post("co_end", "id" => id, "d" => { "x" => "late" })
        join_battle(s, crossed)
        return nil
      end
      unless reply && reply[0] == "co_join"
        log("#{partner} didn't join (#{reply ? reply[1]['why'] : 'no answer'})")
        s.post("co_end", "id" => id, "d" => { "x" => "late" }) if !reply && session
        pbMessage(_INTL("{1} didn't join this battle.", partner))   # instead of a silent wait, then a battle alone
        return nil
      end
      join = read_join(reply[1], max)
      unless join
        log("#{partner}'s party didn't fit; fighting alone")
        tell(:party, _INTL("{1}'s team has a Pokémon this game doesn't have (a mod's, or another KIF's), so you fight alone.", partner))
        session&.post("co_end", "id" => id, "d" => { "x" => "party" })
        return nil
      end
      join[:id] = id
      return join
    end

    def self.read_join(msg, max = 0)
      party = msg["party"].first(max > 0 ? max : 6).map { |h| Mon.load(h, true) }
      return nil if party.empty? || party.any?(&:nil?) || party.none? { |p| p.able? }
      if party.any? { |p| p.instance_variable_get(:@kif_coop_lost) }
        tell(:lost, _INTL("Some of {1}'s Pokémon have moves, Abilities or items this game doesn't have (a mod's, or another KIF's). Here they fight without them.", partner))
      end
      type = Mon.partner_type(msg["type"])
      return { party: party, name: KIF::Net.shown_name(msg["name"]), type: type, tid: msg["tid"], bag: read_bag(msg["items"]) }
    end

    # the partner's battle items: real items with counts, at most 60 (none: it uses none)
    def self.read_bag(h)
      out = {}
      return out unless h.is_a?(Hash)
      h.first(60).each do |k, v|
        it = Mon.sym(k, GameData::Item)
        out[it] = v.clamp(1, 999) if it && v.is_a?(Integer) && v > 0
      end
      return out
    end

    # the first message of these types for this battle (older ones are dropped)
    def self.take_host(id, types)
      @host_box.reject! { |_t, m| m["id"] != id }
      i = @host_box.index { |t, _m| types.include?(t) }
      return i ? @host_box.delete_at(i) : nil
    end

    # on the map: frames go by (nothing moves) until the block is true or secs pass
    def self.wait_map(secs)
      t0 = KIF::Net.now
      loop do
        return true if yield
        return false if !session || KIF::Net.now - t0 > secs
        Graphics.update
        Input.update
        KIF::Net.update
      end
    end

    #---------------------------------------------------------------------------
    # Pokémon over the wire. Received ones are rebuilt here from checked
    # fields; nothing the peer sent becomes a class, method or file name.
    #---------------------------------------------------------------------------
    module Mon
      STATS = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

      module_function

      # a GameData id from a peer string, or nil. Not try_get: that builds a fusion for any
      # B<n>H<n> or _x_ id whatever class was asked (an "ability" that is a species)
      def sym(v, data)
        return nil unless v.is_a?(String) && v =~ /\A[A-Za-z0-9_]{1,40}\z/
        if data == GameData::Species && v =~ /\AB([1-9]\d*)H([1-9]\d*)\z/   # a fusion: canonical, both parents real
          return $1.to_i <= NB_POKEMON && $2.to_i <= NB_POKEMON ? v.to_sym : nil
        end
        d = data::DATA[v.to_sym]
        return d ? d.id : nil
      end

      # a Poke Ball the battle scene, the Summary and the trade scene have pictures for, else
      # a Poke Ball (a Potion as a ball, or a mod's ball without files, would crash them)
      def ball(v)
        b = sym(v, GameData::Item)
        return :POKEBALL unless b && GameData::Item.get(b).is_poke_ball?
        files = ["Graphics/Battle animations/ball_#{b}", "Graphics/Battle animations/ball_#{b}_open", "Graphics/Pictures/Summary/icon_ball_#{b}"]
        return files.all? { |f| pbResolveBitmap(f) } ? b : :POKEBALL
      end

      # the other player's trainer type for the battle screen: PIF draws a
      # partner from Graphics/Trainers/<type> and fails without the file
      def partner_type(v)
        t = sym(v, GameData::TrainerType)
        return t if t && GameData::TrainerType.front_sprite_filename(t)
        return ($Trainer.trainer_type rescue nil) || GameData::TrainerType.keys.first
      end

      def int(v, lo, hi, default = nil)
        return default unless v.is_a?(Integer)
        return v.clamp(lo, hi)
      end

      # text from the peer for a message window: no control codes (\c[...],
      # \se[...] would play files), no tags (<img=file> loads a file and
      # crashes on one that is not a picture), no control or direction characters
      def text(v, max = 300)
        return "" unless v.is_a?(String)
        return KIF::Net.safe_text(v, max)
      end

      # a name or a line the game draws through its tag parser: no < > & either (<img=..>,
      # <icon=..> name files and a missing one ends the game)
      def plain(v, max = 24); v.is_a?(String) ? text(v.delete("<>&"), max).delete("\n") : ""; end

      def name(v); plain(v, 24); end

      def dump(p, full = false)
        h = { "s" => p.species.to_s, "l" => p.level, "n" => p.name.to_s[0, 24], "g" => p.gender.to_i,
              "sh" => p.shiny? ? 1 : 0, "hp" => p.hp, "th" => p.totalhp, "st" => p.status.to_s,
              "f" => p.form.to_i, "eg" => p.egg? ? 1 : 0 }
        KIF::NetSprite.dump_into(h, p) if defined?(KIF::NetSprite)   # sprite key, KIF shiny colours
        return h unless full
        h["x"]  = p.exp
        h["ab"] = p.ability_index
        h["ai"] = p.ability_id.to_s
        h["na"] = p.nature ? p.nature.id.to_s : ""
        h["it"] = p.item_id.to_s
        h["sc"] = p.statusCount.to_i
        h["iv"] = STATS.map { |s| p.iv[s].to_i }
        h["ev"] = STATS.map { |s| p.ev[s].to_i }
        h["ss"] = [p.attack, p.defense, p.spatk, p.spdef, p.speed]
        h["m"]  = p.moves.first(4).map { |m| [m.id.to_s, m.pp.to_i, m.ppup.to_i] }
        h["ha"] = p.happiness.to_i
        h["pb"] = p.poke_ball.to_s
        h["pid"] = p.personalID.to_i & 0xffffffff
        h["ot"] = [p.owner.id.to_i & 0xffffffff, p.owner.name.to_s[0, 24], p.owner.gender.to_i, p.owner.language.to_i] if p.owner
        h["t1"] = p.instance_variable_get(:@type1kuray).to_s if p.instance_variable_get(:@type1kuray)
        h["t2"] = p.instance_variable_get(:@type2kuray).to_s if p.instance_variable_get(:@type2kuray)
        h["to"] = 1 if p.instance_variable_get(:@typeoverwrite)
        return h
      end

      # A Pokémon from checked fields, or nil. full: every battle field (a
      # partner's party, a catch); otherwise what a battle screen shows (HP
      # and the total come from the other game as they are).
      def load(h, full = false, spr = true)
        return nil unless h.is_a?(Hash)
        sp = sym(h["s"], GameData::Species) or return nil
        lv = int(h["l"], 1, GameData::GrowthRate.max_level) or return nil
        p = Pokemon.new(sp, lv, nil, full, false)   # no form check: it can touch the Pokédex
        p.name = name(h["n"]) if h["n"].is_a?(String) && !h["n"].empty?
        g = int(h["g"], 0, 2)
        p.instance_variable_set(:@gender, g) if g
        p.shiny = (h["sh"] == 1)
        f = int(h["f"], 0, 99, 0)
        p.instance_variable_set(:@form, f) if f > 0
        p.steps_to_hatch = 1 if h["eg"] == 1
        st = sym(h["st"], GameData::Status) || :NONE
        p.owner = Pokemon::Owner.new(0, "", 2, 2)
        if full
          return nil unless load_full(p, h, lv)
        end
        th = int(h["th"], 1, 99_999)
        p.instance_variable_set(:@totalhp, th) if th && !full
        p.instance_variable_set(:@hp, int(h["hp"], 0, p.totalhp, p.totalhp))
        p.instance_variable_set(:@status, p.hp > 0 ? st : :NONE)
        KIF::NetSprite.load_into(p, h) if spr && defined?(KIF::NetSprite)
        return p
      rescue StandardError, SystemStackError => e
        KIF::Coop.log("a Pokémon didn't fit (#{e.class}: #{e.message})")
        return nil
      end

      def load_full(p, h, lv)
        gr = p.growth_rate
        lo = gr.minimum_exp_for_level(lv)
        hi = lv >= GameData::GrowthRate.max_level ? lo : gr.minimum_exp_for_level(lv + 1) - 1
        p.exp = int(h["x"], lo, hi, lo)
        p.instance_variable_set(:@level, lv)
        ab = int(h["ab"], 0, 5)
        p.instance_variable_set(:@ability_index, ab) if ab
        ai = sym(h["ai"], GameData::Ability)
        p.instance_variable_set(:@ability, ai) if ai
        lost = !ai && h["ai"].is_a?(String) && !h["ai"].empty?
        na = sym(h["na"], GameData::Nature)
        p.instance_variable_set(:@nature, na) if na
        it = sym(h["it"], GameData::Item)
        p.instance_variable_set(:@item, it)
        lost ||= !it && h["it"].is_a?(String) && !h["it"].empty?   # a mod's item (a Megas stone): held nothing here
        p.statusCount = int(h["sc"], 0, 255, 0)
        iv, ev = h["iv"], h["ev"]
        STATS.each_with_index do |s, i|
          p.iv[s] = int(iv.is_a?(Array) ? iv[i] : nil, 0, Pokemon::IV_STAT_LIMIT, 0)
          p.ev[s] = int(ev.is_a?(Array) ? ev[i] : nil, 0, Pokemon::EV_STAT_LIMIT, 0)
        end
        sent = (h["m"].is_a?(Array) ? h["m"] : []).first(4)
        return false if sent.empty? || !sent.all? { |m| m.is_a?(Array) }
        # a move this game doesn't have (a mod's, another KIF's) is left out, not the
        # whole Pokémon; kept: the sent slot of each move left (Host#finish sends PP back by slot)
        slots = []
        moves = sent.each_with_index.map do |m, k|
          id = sym(m[0], GameData::Move) or next nil
          slots << k
          mv = Pokemon::Move.new(id)
          mv.ppup = int(m[2], 0, 3, 0)
          mv.pp = int(m[1], 0, mv.total_pp, mv.total_pp)
          mv
        end.compact
        moves = [Pokemon::Move.new(:STRUGGLE)] if moves.empty?
        p.moves = moves
        if slots.length < sent.length
          p.instance_variable_set(:@kif_coop_slots, slots)
          lost = true
        end
        p.instance_variable_set(:@kif_coop_lost, true) if lost
        p.happiness = int(h["ha"], 0, 255, 70)
        p.poke_ball = ball(h["pb"])
        p.personalID = int(h["pid"], 0, 0xffffffff, p.personalID)
        if h["ot"].is_a?(Array) && h["ot"].length == 4
          o = h["ot"]
          p.owner = Pokemon::Owner.new(int(o[0], 0, 0xffffffff, 0), name(o[1]), int(o[2], 0, 2, 2), int(o[3], 0, 20, 2))
        end
        t1 = sym(h["t1"], GameData::Type)
        t2 = sym(h["t2"], GameData::Type)
        p.instance_variable_set(:@type1kuray, t1) if t1
        p.instance_variable_set(:@type2kuray, t2) if t2
        p.instance_variable_set(:@typeoverwrite, true) if h["to"] == 1 && (t1 || t2)
        p.calc_stats
        # the stats its own game worked out (IV and EV modes differ per save), up to
        # what the most generous modes could give
        ss = h["ss"]
        th = int(h["th"], 1, 99_999)
        if th && ss.is_a?(Array) && ss.length == 5 && ss.all? { |x| x.is_a?(Integer) && x.between?(1, 99_999) }
          cap = stat_caps(p)
          p.instance_variable_set(:@totalhp, [th, cap[0]].min)
          [:@attack, :@defense, :@spatk, :@spdef, :@speed].each_with_index { |v, i| p.instance_variable_set(v, [ss[i], cap[i + 1]].min) }
        end
        return true
      end

      # the highest each stat (HP first) can be: max level (No Levels mode), IVs and
      # EVs at their limits, a nature for it, the self-fusion boost
      def stat_caps(p)
        lv = GameData::GrowthRate.max_level
        base = p.baseStats
        f = (p.isSelfFusion? rescue false) && defined?(KIF::FusionRules) ? KIF::FusionRules.self_fusion_factor(base.values.sum) : 1
        # a fusion: Fusion BaseStats sliders (custom_bst) can give up to the higher of head and body
        sp = p.species_data
        if sp.is_a?(GameData::FusedSpecies)
          [sp.head_pokemon, sp.body_pokemon].each { |d| STATS.each { |s| base[s] = [base[s].to_i, d.base_stats[s].to_i].max } }
        end
        iv, ev = Pokemon::IV_STAT_LIMIT, Pokemon::EV_STAT_LIMIT
        return STATS.map do |s|
          b = (base[s].to_i * f).round
          s == :HP ? p.send(:calcHP, b, lv, iv, ev) : p.send(:calcStat, b, lv, iv, ev, 110)
        end
      end

      # PP of a partner's Pokémon by the slots its own game sent (nil: a move left
      # out here, its PP stays as it is there)
      def pp_list(p)
        pp = p.moves.map { |m| m.pp.to_i }
        slots = p.instance_variable_get(:@kif_coop_slots) or return pp
        out = []
        slots.each_with_index { |k, i| out[k] = pp[i] }
        return out
      end
    end
  end
end

module KIF
  module Coop
    # On a co-op battle's scene object (both games): the partner's pick shows
    # while this player's command, fight and target menus are up, in the
    # scene's own look (PIF's window skin; EBDX's dark bar)
    module IntentShow
      def pbCommandMenu(*args, &blk); kif_intent(true); super; ensure; kif_intent(false); end
      def pbFightMenu(*args, &blk); kif_intent(true); super; ensure; kif_intent(false); end
      def pbChooseTarget(*args, &blk); kif_intent(true); super; ensure; kif_intent(false); end

      def pbUpdate(*args)
        super
        kif_intent_draw if @kif_intent_on
      end

      def pbEndBattle(*args, &blk)
        super
      ensure
        @kif_intent_win.dispose if @kif_intent_win && !@kif_intent_win.disposed?
        @kif_intent_win = nil
      end

      def kif_intent(on)
        @kif_intent_on = on
        return kif_intent_draw if on
        @kif_intent_win.visible = false if @kif_intent_win && !@kif_intent_win.disposed?
      end

      def kif_intent_draw
        t = KIF::Coop.intent_for(self)
        w = @kif_intent_win
        if !t
          w.visible = false if w && !w.disposed?
          return
        end
        if !w || w.disposed?
          w = @kif_intent_win = kif_intent_make
          @kif_intent_text = nil
        end
        w.visible = true
        return if t == @kif_intent_text
        @kif_intent_text = t
        b = w.bitmap
        b.clear
        if @kif_intent_ebdx
          pbSetSystemFont(b)
          tw = [b.text_size(t).width + 24, Graphics.width].min
          b.fill_rect(0, 0, tw, b.height, Color.new(0, 0, 0, 150))
          pbDrawShadowText(b, 12, 2, tw - 24, b.height - 4, t, Color.new(248, 248, 248), Color.new(64, 64, 64))
        else
          # PIF's scene: a strip in the INFO tab's look, from the left edge to
          # short of this side's data boxes (a long pick is cut there)
          pbSetSmallFont(b)
          tw = [b.text_size(t).width + 16, kif_intent_room].min
          h = b.height
          b.fill_rect(2, 0, tw - 4, h, Color.new(88, 88, 96))
          b.fill_rect(0, 2, tw, h - 4, Color.new(88, 88, 96))
          b.fill_rect(2, 2, tw - 4, h - 4, Color.new(232, 232, 240))
          b.fill_rect(2, h / 2 + 1, tw - 4, h / 2 - 3, Color.new(200, 200, 212))
          b.font.color = Color.new(176, 176, 184)
          b.draw_text(9, 1, tw - 16, h - 2, t)
          b.font.color = Color.new(64, 64, 72)
          b.draw_text(8, 0, tw - 16, h - 2, t)
        end
      rescue StandardError => e
        KIF::Coop.log("partner's pick not shown (#{e.class}: #{e.message})") unless @kif_intent_warned
        @kif_intent_warned = true
      end

      def kif_intent_make
        vp = @viewport
        @kif_intent_ebdx = defined?(PokeBattle_SceneEBDX) && is_a?(PokeBattle_SceneEBDX) ? true : false
        if @kif_intent_ebdx
          s = BitmapSprite.new(Graphics.width, 32, vp)
          s.y = Graphics.height - 140   # over EBDX's command bar
          s.z = 99_999
          return s
        end
        s = BitmapSprite.new(Graphics.width, KIF::Coop::INTENT_H, vp)
        s.x = 4   # in line with the INFO tab
        s.y = KIF::Coop.intent_panel_y(KIF::Coop::INTENT_H)
        s.z = 99_999
        return s
      end

      # width up to this side's data boxes (PIF's scene draws them on the right)
      def kif_intent_room
        sp = @sprites || {}
        xs = sp.keys.select { |k| k.to_s =~ /\AdataBox_\d*[02468]\z/ }.map { |k| sp[k] }.select { |d| d && !(d.disposed? rescue true) }.map(&:x)
        room = (xs.min || Graphics.width / 2) - 4 - 4
        return room.clamp(120, Graphics.width - 8)
      end
    end
  end
end

# PIF's own battle scene draws a partner trainer from its trainer type's
# picture (the other player showed as Red); a co-op partner is drawn as PIF
# draws the player, in their own outfit (EBDX's scene draws both from types)
class PokeBattle_Scene
  alias kif_coop_pbCreateTrainerBackSprite pbCreateTrainerBackSprite unless method_defined?(:kif_coop_pbCreateTrainerBackSprite)

  def pbCreateTrainerBackSprite(idxTrainer, trainerType, numTrainers = 1)
    ret = kif_coop_pbCreateTrainerBackSprite(idxTrainer, trainerType, numTrainers)
    kif_coop_partner_look(idxTrainer)
    return ret
  end

  def kif_coop_partner_look(idx)
    return unless idx == 1 && (look = KIF::Coop.partner_look(self))
    sp = @sprites["player_2"] or return
    ab = generate_front_trainer_sprite_bitmap(false, nil, look["clothes"], look["hat"], look["hat2"], look["hair"],
                                              look["skin"], look["hc"], look["tc"], look["cc"], look["t2c"], false)
    return unless ab && ab.bitmap
    sp.setBitmapDirectly(ab)   # an AnimatedBitmap, as the player's own sprite takes it
    w, h = sp.bitmap.width, sp.bitmap.height
    sp.src_rect = Rect.new(0, 0, w, h)
    sp.ox = w / 2
    sp.oy = h
  rescue StandardError => e
    KIF::Coop.log("partner drawn from the trainer type (#{e.class}: #{e.message})")
  end
end

Events.onMapUpdate += proc { |_sender, _e|
  if KIF::Net.session && defined?(KIF::Coop)
    begin
      KIF::Coop.map_tick
    rescue => e
      KIF::Coop.log("map step failed (#{e.class}: #{e.message})")
    end
  end
}

# a gym's team pick: its limit counts for the partner too, until it is restored
module PokemonSelection
  class << self
    alias kif_coop_choose choose unless method_defined?(:kif_coop_choose) || private_method_defined?(:kif_coop_choose)
    alias kif_coop_restore restore unless method_defined?(:kif_coop_restore) || private_method_defined?(:kif_coop_restore)

    def choose(min = 1, max = 6, *rest, &blk)
      ret = kif_coop_choose(min, max, *rest, &blk)
      KIF::Coop.picked(ret ? max : nil)
      return ret
    end

    def restore(*args)
      KIF::Coop.picked(nil)
      return kif_coop_restore(*args)
    end
  end
end

# an autosave (a win, a catch) inside a shared battle saves this player's own settings,
# not the Multiplayer host's that are live for the battle
module Kernel
  class << self
    alias kif_coop_tryAutosave tryAutosave unless method_defined?(:kif_coop_tryAutosave)

    def tryAutosave(*args)
      return KIF::Coop.saving { kif_coop_tryAutosave(*args) }
    end
  end
end
