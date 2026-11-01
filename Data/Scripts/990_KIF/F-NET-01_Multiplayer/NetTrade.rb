#===============================================================================
# F-NET-01 – Multiplayer: trading with a friend (MULTIPLAYER_PLAN.md
# "Trading with a friend")
#
# Multiplayer > Trade (or yes to the partner's question on the map): each
# player offers one Pokémon from the party or the Boxes (PIF's pickers), sees
# the other's offer (species, level, shiny, nature, ability, item, moves; a
# Summary), and confirms. When this game has sent its OK and has the
# partner's OK for the same pair of offers, it swaps (the received Pokémon
# takes the offered one's slot), plays PIF's trade scene (trade evolutions
# happen there), saves, and says so (tr_done). Either player can cancel until
# their own game has swapped; a cancel or a lost line before then leaves both
# games as they were.
#
# Messages (every field checked again here; a Pokémon is rebuilt from checked
# fields by KIF::Coop::Mon, nothing received is Marshal-loaded):
#   tr_ask   {id}      I want to trade (the same id back = yes)
#   tr_no    {id}      no / I cancelled
#   tr_offer {id,d}    my offer (Mon.dump full + "xt" extras)
#   tr_ok    {id,h}    I confirm these two offers (h: hash of both)
#   tr_done  {id}      I swapped and saved
#   tr_sync  {ids}     on connect: the trade ids my save knows
# No duplicates: the save keeps each swap ($PokemonGlobal @kif_trades) as
# pending (with the Pokémon given) until the partner says tr_done; an id is
# never applied twice. On a reconnect a pending trade the partner's game
# doesn't know (it crashed or quit before saving, or cancelled) is undone:
# the received Pokémon goes, the given one comes back.
#===============================================================================
module KIF
  module Trade
    ID = [Integer, 1, 0x7fffffff]
    { "tr_ask" => { "id" => ID }, "tr_no" => { "id" => ID }, "tr_done" => { "id" => ID },
      "tr_offer" => { "id" => ID, "d" => [Hash] }, "tr_ok" => { "id" => ID, "h" => [String, 16] },
      "tr_sync" => { "ids" => [String, 240] } }.each { |k, v| KIF::Net::TYPES[k] = v }

    KEEP = 20   # finished trade ids kept in the save
    # extra fields a trade carries: Integer => max, or :bool
    EXTRA = { "steps_to_hatch" => 1_000_000, "obtain_method" => 4, "obtain_level" => 1_000, "obtain_map" => 99_999,
              "markings" => 255, "pokerus" => 255, "exp_when_fused_head" => 2**31, "exp_when_fused_body" => 2**31,
              "exp_gained_since_fused" => 2**31, "head_original_ability_index" => 5, "body_original_ability_index" => 5,
              "head_shiny" => :bool, "body_shiny" => :bool, "natural_shiny" => :bool, "glitter" => :bool }

    @st = nil      # the trade on now
    @asked = nil   # the partner's ask not answered yet

    class << self
      attr_accessor :st, :asked
    end

    def self.log(msg); KIF::Net.log("trade: #{msg}"); end
    def self.session; s = KIF::Net.session if KIF::Net.respond_to?(:session); s&.connected? ? s : nil; end
    def self.partner; (s = session) ? KIF::Net.shown_name(s.partner) : "?"; end
    def self.post(t, f = {}); (s = session) ? s.post(t, f) : false; end
    def self.save_game; Game.save; end   # tests replace it

    # the save's record: id => [:pending, Pokémon given, slot, received pid] or :done
    def self.book
      g = $PokemonGlobal
      g.instance_variable_get(:@kif_trades) || g.instance_variable_set(:@kif_trades, {})
    end

    def self.on_connect(_s = nil)
      @st = @asked = nil
      post("tr_sync", "ids" => book.keys.last(KEEP).join(","))
    end

    def self.on_disconnect
      @asked = nil
      @st[:why] ||= :lost if @st && !@st[:done]
    end

    #---------------------------------------------------------------------------
    # Pokémon over the wire
    #---------------------------------------------------------------------------
    def self.dump(p)
      h = KIF::Coop::Mon.dump(p, true)
      x = {}
      EXTRA.each do |k, m|
        v = p.instance_variable_get(:"@#{k}")
        x[k] = v if m == :bool ? (v == true || v == false) : v.is_a?(Integer)
      end
      x["ot_t"] = p.obtain_text.to_s[0, 60] if p.obtain_text.is_a?(String)
      x["fm"] = (p.first_moves || []).first(20).map(&:to_s)
      h["xt"] = x
      return h
    end

    # a Pokémon from the partner's offer, or nil (anything that doesn't fit:
    # unknown species, a move or item this game lacks)
    def self.load(h)
      p = KIF::Coop::Mon.load(h, true) or return nil
      return nil if p.instance_variable_get(:@kif_coop_lost)
      x = h["xt"].is_a?(Hash) ? h["xt"] : {}
      EXTRA.each do |k, m|
        v = x[k]
        ok = m == :bool ? (v == true || v == false) : (v.is_a?(Integer) && v.between?(0, m))
        p.instance_variable_set(:"@#{k}", v) if ok
      end
      p.obtain_text = KIF::Coop::Mon.text(x["ot_t"], 60).delete("\n") if x["ot_t"].is_a?(String)
      fm = x["fm"].is_a?(Array) ? x["fm"].first(20).map { |m| KIF::Coop::Mon.sym(m, GameData::Move) }.compact : []
      p.first_moves = fm unless fm.empty?
      return p
    rescue StandardError => e
      log("an offer didn't fit (#{e.class}: #{e.message})")
      return nil
    end

    # both offers, the host's first: what each OK is for
    def self.digest
      a, b = KIF::Net::Wire.json(@st[:md]), KIF::Net::Wire.json(@st[:td])
      a, b = b, a unless session&.role == :host
      return KIF::Net::Crypto.hex(KIF::Net::Crypto.sha256("#{a}|#{b}"))[0, 16]
    end

    #---------------------------------------------------------------------------
    # The trade's steps (the screen below calls these; so do the tests)
    #---------------------------------------------------------------------------
    def self.start
      id = @asked || ((KIF::Net::Crypto.random(4).unpack1("N") & ID[2]) | 1)
      @st = { id: id, open: !@asked.nil?, v: 0 }
      @asked = nil
      post("tr_ask", "id" => id)
    end

    def self.changed; @st[:v] += 1 if @st; end

    def self.offer(p, loc)
      d = dump(p)
      @st.merge!(mine: p, loc: loc, md: KIF::Net::Wire.parse(KIF::Net::Wire.json(d)), ok: false, their_ok: false)
      changed
      post("tr_offer", "id" => @st[:id], "d" => d)
    end

    def self.ready?
      st = @st
      return st && st[:open] && st[:mine] && st[:theirs] && !st[:why] && !st[:done] ? true : false
    end

    def self.confirm
      return false unless ready?
      @st[:ok] = true
      changed
      post("tr_ok", "id" => @st[:id], "h" => digest)
      commit if @st[:their_ok]
      return true
    end

    def self.cancel
      st = @st or return
      return if st[:done] || st[:why]
      st[:why] = :me
      post("tr_no", "id" => st[:id])
    end

    # both OK'd the same pair: swap, recorded as pending until the partner's tr_done
    def self.commit
      st = @st
      box, i = st[:loc]
      unless $PokemonStorage[box, i].equal?(st[:mine])   # moved meanwhile
        log("#{st[:id]}: the offered Pokémon isn't where it was; cancelled")
        return cancel
      end
      p = st[:theirs]
      p.obtain_method = 2   # traded, as pbStartTrade marks it
      KIF::NetSprite.forget(p) if defined?(KIF::NetSprite)   # it is the player's own now: its own sprite picks, not the partner's picture
      $Trainer.pokedex.register(p)
      $Trainer.pokedex.set_owned(p.species)
      $Trainer.stats.incr_nb_trades if $Trainer.respond_to?(:stats) && $Trainer.stats.respond_to?(:incr_nb_trades)
      book[st[:id]] = [:pending, Marshal.load(Marshal.dump(st[:mine])), [box, i], p.personalID]
      $PokemonStorage[box, i] = p
      st[:done] = true
      changed
      log("#{st[:id]}: gave #{st[:mine].species} for #{p.species}")
    end

    # after the trade scene: saved, so the partner may count it as done
    def self.finish
      st = @st or return
      if save_game
        post("tr_done", "id" => st[:id])
      else
        log("#{st[:id]}: not saved; resolved on the next connection")
      end
      prune
    end

    def self.prune
      done = book.keys.select { |k| book[k] == :done }
      done.first([done.length - KEEP, 0].max).each { |k| book.delete(k) }
    end

    # the partner's game never swapped: the received Pokémon goes, the given one comes back
    def self.undo(id)
      e = book.delete(id)
      return unless e.is_a?(Array)
      _, gave, loc, pid = e
      spot = find(pid)
      if spot
        $PokemonStorage[*spot] = gave
      elsif $PokemonStorage[*loc].nil?
        $PokemonStorage[*loc] = gave
      elsif !pbAddPokemonSilent(gave)
        log("#{id}: no room to give #{gave.species} back")
      end
      log("#{id}: undone (#{spot ? 'received one taken back' : 'received one not found'})")
      KIF::Net.notes << _INTL("The trade with {1} didn't finish on their side. {2} is back with you.", partner, gave.name)
    end

    def self.find(pid)
      $Trainer.party.each_with_index { |q, i| return [-1, i] if q && q.personalID == pid }
      $PokemonStorage.maxBoxes.times do |b|
        $PokemonStorage.maxPokemon(b).times { |i| q = $PokemonStorage[b, i]; return [b, i] if q && q.personalID == pid }
      end
      return nil
    end

    def self.sync(text)
      theirs = text.split(",").map(&:to_i)
      book.keys.each do |id|
        next unless book[id].is_a?(Array)
        theirs.include?(id) ? book[id] = :done : undo(id)
      end
    end

    # Messages from the partner's game (KIF::Net.update)
    def self.receive(type, msg)
      id = msg["id"]
      case type
      when "tr_sync" then return sync(msg["ids"])
      when "tr_done"
        book[id] = :done if book[id].is_a?(Array)
        return
      when "tr_no"
        @asked = nil if @asked == id
        return undo(id) if book[id].is_a?(Array)   # cancelled after this game swapped: it never did
        if @st && @st[:id] == id && !@st[:done]
          @st[:why] ||= :them
          changed
        end
        return
      when "tr_ask"
        return if book.key?(id)   # an old one, sent again
        if !@st then @asked = id
        elsif @st[:id] == id then @st[:open] = true
        elsif !@st[:open] && session&.role != :host   # both asked at once: the host's id counts
          @st[:id] = id
          @st[:open] = true
          post("tr_ask", "id" => id)
        end
        changed
        return
      end
      st = @st
      return unless st && st[:id] == id && st[:open] && !st[:done] && !st[:why]
      case type
      when "tr_offer"
        st[:theirs] = load(msg["d"])
        st[:td] = msg["d"]
        st[:bad] = st[:theirs].nil?
        st[:ok] = st[:their_ok] = false
        log("#{id}: an offer that doesn't fit this game") if st[:bad]
      when "tr_ok"
        st[:their_ok] = st[:md] && st[:td] && msg["h"] == digest ? true : false
        commit if st[:ok] && st[:their_ok]
      end
      changed
    end

    #---------------------------------------------------------------------------
    # Screens
    #---------------------------------------------------------------------------
    def self.menu_label; @asked ? _INTL("Trade: {1} asked", partner) : _INTL("Trade"); end

    def self.menu_pick(_scr = nil)
      return KIF::Presence.busy("trade") { run } if defined?(KIF::Presence)
      run
    end

    # the partner asked: a question at a quiet moment on the map
    def self.map_tick
      return unless @asked && !@st && KIF::Net.quiet?
      id = @asked
      yes = pbConfirmMessage(_INTL("{1} wants to trade Pokémon. Trade now?", partner))
      return unless @asked == id && session
      return menu_pick if yes
      @asked = nil
      post("tr_no", "id" => id)
    end

    def self.describe(p)
      return [_INTL("nothing yet")] unless p
      return [_INTL("an Egg")] if p.egg?
      l1 = _INTL("{1} Lv. {2}", p.speciesName, p.level)
      l1 += _INTL(", shiny") if p.shiny?
      l2 = [p.nature ? p.nature.name : "-", p.ability ? p.ability.name : "-",
            p.item ? _INTL("holds {1}", p.item.name) : _INTL("no item")].join(", ")
      return [l1, l2, p.moves.map { |m| m.name }.join(", ")]
    end

    def self.view
      st = @st
      who = partner
      unless st[:open]
        return [_INTL("Trade\nWaiting for {1} to answer...", who), [_INTL("Cancel")], [:cancel]]
      end
      lines = [_INTL("Trade with {1}", who), _INTL("You offer: {1}", describe(st[:mine])[0])]
      theirs = st[:bad] ? [_INTL("a Pokémon your game can't take")] : describe(st[:theirs])
      lines << _INTL("{1} offers: {2}", who, theirs[0])
      theirs[1..].each { |l| lines << "  #{l}" }
      lines << (st[:their_ok] ? _INTL("{1} confirmed.", who) : st[:ok] ? _INTL("Waiting for {1} to confirm...", who) : "")
      cmds, acts = [], []
      add = proc { |t, a| cmds << t; acts << a }
      add.call(st[:mine] ? _INTL("Change your offer") : _INTL("Offer a Pokémon"), :offer) unless st[:ok]
      add.call(_INTL("Summary: {1}'s Pokémon", who), :summary) if st[:theirs]
      add.call(_INTL("Confirm the trade"), :confirm) if ready? && !st[:ok]
      add.call(_INTL("Cancel"), :cancel)
      return [lines.join("\n"), cmds, acts]
    end

    def self.choose
      c = pbMessage(_INTL("Offer a Pokémon from where?"), [_INTL("Party"), _INTL("Boxes"), _INTL("Cancel")], 3)
      loc = nil
      if c == 0
        pbFadeOutIn {
          screen = PokemonPartyScreen.new(PokemonParty_Scene.new, $Trainer.party)
          screen.pbStartScene(_INTL("Choose a Pokémon to offer."), false)
          i = screen.pbChoosePokemon
          screen.pbEndScene
          loc = [-1, i] if i && i >= 0
        }
      elsif c == 1
        pbFadeOutIn { loc = PokemonStorageScreen.new(PokemonStorageScene.new, $PokemonStorage).pbChoosePokemon }
      end
      p = loc && $PokemonStorage[loc[0], loc[1]]
      return unless p && @st
      if loc[0] == -1 && !p.egg? && p.hp > 0 && $Trainer.able_pokemon_count <= 1
        return pbMessage(_INTL("That's your last Pokémon that can battle."))
      end
      offer(p, loc)
    end

    def self.why_text(why)
      case why
      when :them then _INTL("{1} stopped the trade. Nothing was traded.", partner)
      when :lost then _INTL("The connection was lost. Nothing was traded.")
      end
    end

    def self.run
      start
      m = KIF::Net::Menu
      own = m.instance_variable_get(:@scr).nil?
      m.instance_variable_set(:@scr, KIF::Net::Screen.new) if own
      loop do
        st = @st
        break unless st
        if st[:done]
          pbFadeOutInWithMusic {
            sc = PokemonTrade_Scene.new
            sc.pbStartScreen(st[:mine], st[:theirs], $Trainer.name, partner)
            sc.pbTrade
            sc.pbEndScreen   # trade evolutions
          }
          finish
          break
        end
        if st[:why]
          t = why_text(st[:why])
          pbMessage(t) if t
          break
        end
        head, cmds, acts = view
        r = m.pick(head, cmds, "", proc { [@st && @st[:v], session.nil?] })
        next if r.nil?
        a = r < 0 ? :cancel : acts[r]
        case a
        when :offer then choose
        when :summary
          pbFadeOutIn { PokemonSummaryScreen.new(PokemonSummary_Scene.new, true).pbStartScreen([st[:theirs]], 0, false) }
        when :confirm then confirm
        when :cancel
          cancel if @st && !@st[:done] && (!st[:mine] || pbConfirmMessage(_INTL("Stop trading?")))
        end
      end
    ensure
      cancel
      @st = nil
      if own
        m.instance_variable_get(:@scr)&.dispose
        m.instance_variable_set(:@scr, nil)
      end
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e|
  if KIF::Net.session
    begin
      KIF::Trade.map_tick
    rescue => e
      KIF::Trade.log("map step failed (#{e.class}: #{e.message})")
    end
  end
}
