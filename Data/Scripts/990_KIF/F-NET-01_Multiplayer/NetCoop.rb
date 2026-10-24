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
#   co_ask   {id,map,kind}          host: a battle starts here, join?
#   co_join  {id,name,type,tid,party}  guest: yes, with this party
#   co_no    {id,why}               guest: not now
#   co_begin {id,d}                 host: trainers, parties, battlers
#   co_ev    {id,e}                 host: what its battle scene showed
#   co_cmd / co_act {id,d}          a turn: host asks, guest answers
#   co_sw / co_swr  {id,d}          a replacement: host asks, guest answers
#   co_end   {id,d}                 host: result, the guest's party, Exp, catches
#===============================================================================
module KIF
  module Coop
    {
      "co_pact"  => { "on" => [Integer, 0, 1] },
      "co_st"    => { "map" => [Integer, 0, 99_999] },
      "co_ask"   => { "id" => [Integer, 1, 1_000_000_000], "map" => [Integer, 0, 99_999], "kind" => [String, 8] },
      "co_join"  => { "id" => [Integer, 1, 1_000_000_000], "name" => [String, 24], "type" => [String, 48],
                      "tid" => [Integer, 0, 0xffffffff], "party" => [Array] },
      "co_no"    => { "id" => [Integer, 1, 1_000_000_000], "why" => [String, 16] },
      "co_begin" => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_ev"    => { "id" => [Integer, 1, 1_000_000_000], "e" => [Array] },
      "co_cmd"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_act"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_sw"    => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_swr"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
      "co_end"   => { "id" => [Integer, 1, 1_000_000_000], "d" => [Hash] },
    }.each { |k, v| KIF::Net::TYPES[k] = v }

    HOST_TYPES  = %w[co_join co_no co_act co_swr]
    GUEST_TYPES = %w[co_begin co_ev co_cmd co_sw co_end]

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

    class << self
      attr_accessor :ask_wait, :quiet_wait, :begin_wait, :cmd_wait, :sw_wait
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
      return false unless defined?(KIF::AutoBattle) && KIF::AutoBattle.on?
      return !defined?(KIF::Modules) || KIF::Modules.active?("F-BATTLE-02_AutoBattle")
    end

    def self.on_connect(_s = nil)
      @want = @their = @ask_pact = false
      @their_map = @sent_map = @ask = nil
      @host_box.clear
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
    end

    # the row on the Multiplayer connected screen
    def self.menu_label
      return _INTL("Fight together: On") if on?
      return _INTL("Fight together: Asked") if @want
      return _INTL("Fight together: Off")
    end

    def self.menu_pick(_scr = nil)
      if @want
        return unless pbConfirmMessage(_INTL("Stop fighting together with {1}?", partner))
        set_want(false)
        @notes << _INTL("You stopped fighting together.")
        return
      end
      pbMessage(_INTL("Fighting together: a battle either of you starts while the other is on the same map becomes a double battle. Each of you uses your own Pokémon."))
      return unless pbConfirmMessage(_INTL("Ask {1} to fight together?", partner))
      set_want(true)
      @notes << (on? ? _INTL("You now fight together with {1}.", partner) : _INTL("Asked {1}. They need to say yes.", partner))
    end

    # the partner asked: a question at a quiet moment on the map
    def self.ask_pact
      @ask_pact = false
      return if @want || !@their
      yes = pbConfirmMessage(_INTL("{1} wants to fight together: battles either of you starts on the same map become double battles. OK?", partner))
      return unless session && @their
      set_want(yes)
      @notes << _INTL("You now fight together with {1}.", partner) if yes
    end

    #---------------------------------------------------------------------------
    # Messages from the partner's game (KIF::Net.update)
    #---------------------------------------------------------------------------
    def self.receive(type, msg)
      case type
      when "co_pact"
        was = @their
        @their = msg["on"] == 1
        @ask_pact = @their && !@want
        @notes << _INTL("{1} stopped fighting together.", partner) if was && !@their && @want
        send_status if @their
      when "co_st" then @their_map = msg["map"]
      when "co_ask" then guest_ask(msg)
      when *HOST_TYPES then @host_box << [type, msg]
      when *GUEST_TYPES
        if @guest
          @guest.feed(type, msg)
        elsif type == "co_end" && @ask && @ask["id"] == msg["id"]
          @ask = nil   # the host gave up before this game was free
        end
      end
    end

    def self.take_notes; n = @notes.dup; @notes.clear; n; end

    #---------------------------------------------------------------------------
    # Guest: the partner's battle starts; join when this game is free
    #---------------------------------------------------------------------------
    def self.guest_ask(msg)
      s = session or return
      return s.post("co_no", "id" => msg["id"], "why" => "off") unless on?
      return s.post("co_no", "id" => msg["id"], "why" => "busy") if @guest || @ask || $game_temp&.in_battle
      @ask = msg
      @ask_at = KIF::Net.now
    end

    # every frame on the map
    def self.map_tick
      s = session or return
      send_status if $game_map && $game_map.map_id != @sent_map && (@want || @their)
      if @ask
        ask = @ask
        why = if !on? then "off"
              elsif ask["map"] != $game_map.map_id then "map"
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

    def self.join_data(id, trainer)
      return { "id" => id, "name" => trainer.name.to_s[0, 24], "type" => trainer.trainer_type.to_s[0, 48],
               "tid" => trainer.id.to_i & 0xffffffff, "party" => trainer.party.first(6).map { |p| Mon.dump(p, true) } }
    end

    def self.join_battle(s, ask)
      s.post("co_join", join_data(ask["id"], $Trainer))
      log("joining #{partner}'s battle #{ask['id']}")
      g = Guest.new(s, ask["id"], $Trainer)
      @guest = g
      begin
        g.run
      rescue StandardError => e
        log("guest battle failed (#{e.class}: #{e.message})")
        (s.post("co_act", "id" => ask["id"], "d" => { "a" => "auto", "b" => -1 }) rescue nil)
      ensure
        @guest = nil
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
      s.post("co_ask", "id" => id, "map" => ($game_map ? $game_map.map_id : 0), "kind" => kind.to_s)
      reply = nil
      wait_map(@ask_wait) { reply = take_host(id, %w[co_join co_no]) }
      unless reply && reply[0] == "co_join"
        log("#{partner} didn't join (#{reply ? reply[1]['why'] : 'no answer'})")
        s.post("co_end", "id" => id, "d" => { "x" => "late" }) if !reply && session
        return nil
      end
      join = read_join(reply[1])
      unless join
        log("#{partner}'s party didn't fit; fighting alone")
        session&.post("co_end", "id" => id, "d" => { "x" => "party" })
        return nil
      end
      join[:id] = id
      return join
    end

    def self.read_join(msg)
      party = msg["party"].first(6).map { |h| Mon.load(h, true) }
      return nil if party.empty? || party.any?(&:nil?) || party.none? { |p| p.able? }
      type = Mon.sym(msg["type"], GameData::TrainerType) || ($Trainer.trainer_type rescue :YOUNGSTER)
      return { party: party, name: KIF::Net.shown_name(msg["name"]), type: type, tid: msg["tid"] }
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

      # a GameData id from a peer string, or nil
      def sym(v, data)
        return nil unless v.is_a?(String) && v =~ /\A[A-Za-z0-9_]{1,40}\z/
        d = data.try_get(v.to_sym)
        return d ? d.id : nil
      end

      def int(v, lo, hi, default = nil)
        return default unless v.is_a?(Integer)
        return v.clamp(lo, hi)
      end

      # text from the peer for a message window: no control codes (\c[...],
      # \se[...] would play files), no control characters
      def text(v, max = 300)
        return "" unless v.is_a?(String)
        return v.gsub("\r\n", "\n").gsub(/[\\\x00-\x09\x0b-\x1f\x7f]/, "")[0, max]
      end

      def name(v); text(v, 24).delete("\n"); end

      def dump(p, full = false)
        h = { "s" => p.species.to_s, "l" => p.level, "n" => p.name.to_s[0, 24], "g" => p.gender.to_i,
              "sh" => p.shiny? ? 1 : 0, "hp" => p.hp, "th" => p.totalhp, "st" => p.status.to_s,
              "f" => p.form.to_i, "eg" => p.egg? ? 1 : 0 }
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
      def load(h, full = false)
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
        return p
      rescue StandardError => e
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
        na = sym(h["na"], GameData::Nature)
        p.instance_variable_set(:@nature, na) if na
        it = sym(h["it"], GameData::Item)
        p.instance_variable_set(:@item, it)
        p.statusCount = int(h["sc"], 0, 255, 0)
        iv, ev = h["iv"], h["ev"]
        STATS.each_with_index do |s, i|
          p.iv[s] = int(iv.is_a?(Array) ? iv[i] : nil, 0, Pokemon::IV_STAT_LIMIT, 0)
          p.ev[s] = int(ev.is_a?(Array) ? ev[i] : nil, 0, Pokemon::EV_STAT_LIMIT, 0)
        end
        moves = (h["m"].is_a?(Array) ? h["m"] : []).first(4).map do |m|
          next nil unless m.is_a?(Array)
          id = sym(m[0], GameData::Move) or next nil
          mv = Pokemon::Move.new(id)
          mv.ppup = int(m[2], 0, 3, 0)
          mv.pp = int(m[1], 0, mv.total_pp, mv.total_pp)
          mv
        end
        return false if moves.empty? || moves.include?(nil)
        p.moves = moves
        p.happiness = int(h["ha"], 0, 255, 70)
        p.poke_ball = sym(h["pb"], GameData::Item) || :POKEBALL
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
        # the stats its own game worked out (IV and EV modes differ per save)
        ss = h["ss"]
        th = int(h["th"], 1, 99_999)
        if th && ss.is_a?(Array) && ss.length == 5 && ss.all? { |x| x.is_a?(Integer) && x.between?(1, 99_999) }
          p.instance_variable_set(:@totalhp, th)
          [:@attack, :@defense, :@spatk, :@spdef, :@speed].each_with_index { |v, i| p.instance_variable_set(v, ss[i]) }
        end
        return true
      end
    end
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
