#===============================================================================
# F-NET-01 – Multiplayer: trading with a friend (MULTIPLAYER_PLAN.md
# "Trading with a friend")
#
# Multiplayer > Trade (or yes to the partner's question on the map): each
# player offers one Pokémon from the party or the Boxes (PIF's pickers), sees
# the other's offer (species, level, shiny, nature, ability, item, moves; a
# Summary), and confirms. The game that confirmed first swaps when the
# partner's OK for the same pair of offers arrives and answers tr_go; the game
# that confirmed second swaps on that tr_go (so a lost OK can't leave one game
# swapped alone). Then PIF's trade scene (trade evolutions happen there), a
# save, and tr_done. Either player can cancel until their own game has
# swapped; a cancel or a lost line before then leaves both games as they were.
#
# Messages (every field checked again here; a Pokémon is rebuilt from checked
# fields by KIF::Coop::Mon, nothing received is Marshal-loaded):
#   tr_ask   {id}      I want to trade (the same id back = yes)
#   tr_no    {id}      no / I cancelled
#   tr_offer {id,d}    my offer (Mon.dump full + "xt" extras)
#   tr_ok    {id,h}    I confirm these two offers (h: hash of both)
#   tr_go    {id,h}    I swapped on your OK for these two offers
#   tr_done  {id}      I swapped and saved
#   tr_sync  {ids}     on connect: the trade ids my save knows (8 hex digits each)
# No duplicates: the save keeps each swap ($PokemonGlobal @kif_trades) as
# pending (with the Pokémon given) until the partner says tr_done; an id is
# never applied twice. On a reconnect a pending trade the partner's game
# doesn't know (it crashed or quit before saving, or cancelled) is undone:
# the received Pokémon goes, the given one comes back. That happens only for
# the partner the trade was made with (by name), only while the received
# Pokémon is the one that came (found by a tag this game put on it, not by
# anything the partner sent) and unchanged, never during a battle, and not
# after EXPIRE seconds.
#===============================================================================
module KIF
  module Trade
    ID = [Integer, 1, 0x7fffffff]
    { "tr_ask" => { "id" => ID }, "tr_no" => { "id" => ID }, "tr_done" => { "id" => ID },
      "tr_offer" => { "id" => ID, "d" => [Hash] }, "tr_ok" => { "id" => ID, "h" => [String, 16] },
      "tr_go" => { "id" => ID, "h" => [String, 16] },
      "tr_sync" => { "ids" => [String, 240] } }.each { |k, v| KIF::Net::TYPES[k] = v }

    KEEP = 20             # finished trade ids kept in the save
    LIST = 30             # ids in one tr_sync (8 hex digits each: 240 characters); a full list may be cut
    EXPIRE = 3 * 86_400   # seconds; a trade still pending after this is final
    MAX_OFFER = 12_000    # bytes of JSON in an offer (a Pokémon with its fusion halves is a few KB)
    BURST = 10            # offers and OKs worked on at once; then RATE more a second
    RATE = 5.0
    MUTE = 60             # seconds the partner's asks are ignored after two No answers
    # extra fields a trade carries: Integer => max (0..max), a Range, or :bool
    EXTRA = { "steps_to_hatch" => 1_000_000, "obtain_method" => 4, "obtain_level" => 1_000, "obtain_map" => 99_999,
              "markings" => 255, "pokerus" => 255, "exp_when_fused_head" => 2**31, "exp_when_fused_body" => 2**31,
              "exp_gained_since_fused" => 2**31, "head_original_ability_index" => 5, "body_original_ability_index" => 5,
              "head_shiny" => :bool, "body_shiny" => :bool, "natural_shiny" => :bool, "glitter" => :bool,
              "cool" => 255, "beauty" => 255, "cute" => 255, "smart" => 255, "tough" => 255, "sheen" => 255,
              "timeEggHatched" => 2**32, "hatched_map" => 99_999,   # obtain_method 1 (hatched) shows them in the Summary
              "hat" => 1..9999, "hat_x" => -999..999, "hat_y" => -999..999,
              "hat_mirrored_horizontal" => :bool, "hat_mirrored_vertical" => :bool }

    KIF::Net::TYPE_MAX["tr_offer"] = MAX_OFFER + 256   # the offer and the frame's id, type and number
    KIF::Net::TYPE_NODES["tr_offer"] = 1_000           # values: a fusion with both halves, 60 ribbons each, has ~490

    @st = nil      # the trade on now
    @asked = nil   # the partner's ask not answered yet
    @line = nil    # per line (one session): No answers, the mute, undo work held back during a battle

    class << self
      attr_accessor :st, :asked
    end

    def self.log(msg); KIF::Net.log("trade: #{msg}"); end
    def self.session; s = KIF::Net.session if KIF::Net.respond_to?(:session); s&.connected? ? s : nil; end
    def self.partner; (s = session) ? KIF::Net.shown_name(s.partner) : "?"; end
    def self.post(t, f = {}); (s = session) ? s.post(t, f) : false; end
    def self.save_game; Game.save; end   # tests replace it

    def self.line
      s = session
      @line = { s: s, declines: 0, mute: nil, later: [] } unless @line && s && @line[:s].equal?(s)
      return @line
    end

    # the save's record: id => [:pending, Pokémon given, slot, tag, partner, fingerprint, time, Pokédex] or :done
    def self.book
      g = $PokemonGlobal
      g.instance_variable_get(:@kif_trades) || g.instance_variable_set(:@kif_trades, {})
    end

    def self.on_connect(_s = nil)
      @st = @asked = nil
      post("tr_sync", "ids" => book.keys.last(LIST).map { |i| format("%08x", i) }.join)
    end

    def self.on_disconnect
      @asked = nil
      @st[:why] ||= :lost if @st && !@st[:done]
    end

    # offers and OKs worked on: a burst, then a few a second (a flood costs the game thread)
    def self.allow?(st)
      t = KIF::Net.now
      st[:tok] = [(st[:tok] || BURST) + (t - (st[:tok_t] || t)) * RATE, BURST].min
      st[:tok_t] = t
      return false if st[:tok] < 1
      st[:tok] -= 1
      return true
    end

    #---------------------------------------------------------------------------
    # Pokémon over the wire
    #---------------------------------------------------------------------------
    def self.dump(p, nested = false)
      h = KIF::Coop::Mon.dump(p, true)
      x = {}
      EXTRA.each do |k, m|
        v = p.instance_variable_get(:"@#{k}")
        x[k] = v if m == :bool ? (v == true || v == false) : v.is_a?(Integer)
      end
      x["ot_t"] = p.obtain_text.to_s[0, 60] if p.obtain_text.is_a?(String)
      x["fm"] = (p.first_moves || []).first(20).map(&:to_s)
      x["rb"] = p.ribbons.first(60).map { |r| r.is_a?(Integer) ? r : r.to_s } if p.ribbons.is_a?(Array) && !p.ribbons.empty?
      im = KIF::Coop::Mon::STATS.select { |s| p.ivMaxed.is_a?(Hash) && p.ivMaxed[s] }
      x["im"] = im.map(&:to_s) unless im.empty?
      unless nested   # a fusion's two halves (what unfusing gives back), one level only
        x["oh"] = dump(p.original_head, true) if p.original_head.is_a?(Pokemon)
        x["ob"] = dump(p.original_body, true) if p.original_body.is_a?(Pokemon)
      end
      h["xt"] = x
      return h
    end

    # a Pokémon from the partner's offer, or nil (anything that doesn't fit:
    # unknown species, a move or item this game lacks)
    def self.load(h, nested = false)
      p = KIF::Coop::Mon.load(h, true) or return nil
      return nil if p.instance_variable_get(:@kif_coop_lost)
      x = h["xt"].is_a?(Hash) ? h["xt"] : {}
      EXTRA.each do |k, m|
        v = x[k]
        ok = m == :bool ? (v == true || v == false) : (v.is_a?(Integer) && (m.is_a?(Range) ? m : (0..m)).cover?(v))
        p.instance_variable_set(:"@#{k}", v) if ok
      end
      # a hatched Pokémon without its time (an offer that left it out) would break the Summary's memo
      p.instance_variable_set(:@timeEggHatched, 0) if p.obtain_method == 1 && !p.instance_variable_get(:@timeEggHatched).is_a?(Integer)
      p.obtain_text = KIF::Coop::Mon.plain(x["ot_t"], 60) if x["ot_t"].is_a?(String)
      fm = x["fm"].is_a?(Array) ? x["fm"].first(20).map { |m| KIF::Coop::Mon.sym(m, GameData::Move) }.compact : []
      p.first_moves = fm unless fm.empty?
      if x["rb"].is_a?(Array)   # a ribbon is its id, or a number a Ribbon is also listed by
        p.ribbons = x["rb"].first(60).map { |r| r.is_a?(Integer) ? (r if GameData::Ribbon::DATA.key?(r)) : KIF::Coop::Mon.sym(r, GameData::Ribbon) }.compact.uniq
      end
      stats = KIF::Coop::Mon::STATS
      (x["im"].is_a?(Array) ? x["im"] : []).each { |s| p.ivMaxed[s.to_sym] = true if stats.map(&:to_s).include?(s) }
      unless nested
        { "oh" => :original_head=, "ob" => :original_body= }.each do |k, w|
          o = x[k].is_a?(Hash) ? load(x[k], true) : nil
          p.send(w, o) if o
        end
      end
      legal!(p)
      return nil if defined?(KIF::Nuzlocke) && KIF::Nuzlocke.on? && !p.egg? && p.hp <= 0   # a dead Pokémon can't come back by trade (NSL-04)
      return p
    rescue StandardError => e
      log("an offer didn't fit (#{e.class}: #{e.message})")
      return nil
    end

    # what the wire can't vouch for: an ability, held item, moves, EVs and gender this
    # species can't have are replaced by what it can (a trade mints nothing)
    def self.legal!(p)
      sd = p.species_data
      p.instance_variable_set(:@ability, nil) unless (sd.abilities + sd.hidden_abilities).compact.include?(p.ability_id)
      p.instance_variable_set(:@item, nil) if p.item && !p.item.can_hold?
      p.moves = p.moves.uniq(&:id)
      tot = p.ev.values.sum
      p.ev.each_key { |s| p.ev[s] = p.ev[s] * Pokemon::EV_LIMIT / tot } if tot > Pokemon::EV_LIMIT
      fixed = { AlwaysMale: 0, AlwaysFemale: 1, Genderless: 2 }[sd.gender_ratio]
      if fixed then p.instance_variable_set(:@gender, fixed)
      elsif p.instance_variable_get(:@gender) == 2 then p.instance_variable_set(:@gender, nil)   # worked out again
      end
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
      id = @asked
      id ||= loop do   # not an id the save's book holds: commit would overwrite that escrow
        i = (KIF::Net::Crypto.random(4).unpack1("N") & ID[2]) | 1
        break i unless book.key?(i)
      end
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

    # expected: the digest of the pair the screen showed when the player pressed Confirm; if the
    # partner's offer changed since, nothing is signed
    def self.confirm(expected = nil)
      return false unless ready?
      return false if expected && expected != digest
      st = @st
      st[:second] = st[:their_ok]   # the partner's OK was in already: swap on its tr_go, not before
      st[:ok] = true
      changed
      post("tr_ok", "id" => st[:id], "h" => digest)
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
      tag = KIF::Net::Crypto.hex(KIF::Net::Crypto.random(8))
      p.instance_variable_set(:@kif_trade_tag, tag)   # how undo finds it again (nothing the partner sent)
      KIF::NetSprite.forget(p) if defined?(KIF::NetSprite)   # the partner's picture isn't kept
      dex = $Trainer.pokedex
      seen = [p.species, dex.seen?(p.species) ? true : false, dex.owned?(p.species) ? true : false]
      dex.register(p)
      dex.set_owned(p.species)
      trades(1)
      book[st[:id]] = [:pending, Marshal.load(Marshal.dump(st[:mine])), [box, i], tag, partner, fingerprint(p), Time.now.to_i, seen]
      $PokemonStorage[box, i] = p
      KIF::Nuzlocke.gift_received(p, true) if defined?(KIF::Nuzlocke)   # Gift Pokémon: Counts applies to a trade (NSL-04)
      st[:done] = true
      changed
      log("#{st[:id]}: gave #{st[:mine].species} for #{p.species}")
    end

    def self.trades(n)
      s = $Trainer.stats if $Trainer.respond_to?(:stats)
      return unless s && s.respond_to?(:incr_nb_trades)
      n > 0 ? s.incr_nb_trades : s.instance_variable_set(:@nb_trades, [s.instance_variable_get(:@nb_trades).to_i - 1, 0].max)
    end

    # what undo compares: the received Pokémon unchanged since (a level, a move, an item, a
    # nickname, an evolution or a fusion make it the player's own)
    def self.fingerprint(p); [p.species, p.exp, p.item_id, p.name, p.moves.map(&:id)]; end

    # after the trade scene: saved, so the partner may count it as done
    def self.finish
      st = @st or return
      return unless st[:done]
      e = book[st[:id]]
      e[5] = fingerprint(st[:theirs]) if e.is_a?(Array)   # the scene may have evolved it
      if save_game
        post("tr_done", "id" => st[:id])
      else
        log("#{st[:id]}: not saved; resolved on the next connection")
      end
      prune
    end

    def self.prune
      now = Time.now.to_i
      book.each { |k, e| book[k] = :done if e.is_a?(Array) && now - e[6].to_i > EXPIRE }
      done = book.keys.select { |k| book[k] == :done }
      done.first([done.length - KEEP, 0].max).each { |k| book.delete(k) }
    end

    # every Pokémon held, with its slot: party first, then the Boxes
    def self.stored
      l = []
      $Trainer.party.each_with_index { |q, i| l << [q, [-1, i]] if q }
      $PokemonStorage.maxBoxes.times do |b|
        $PokemonStorage.maxPokemon(b).times { |i| q = $PokemonStorage[b, i]; l << [q, [b, i]] if q }
      end
      return l
    end

    def self.find(pid)
      stored.each { |q, spot| return spot if q.personalID == pid }
      return nil
    end

    # a slot that is empty and inside the party (its next place) or a Box
    def self.free?(box, i)
      return false unless box.is_a?(Integer) && i.is_a?(Integer) && i >= 0 && box >= -1 && box < $PokemonStorage.maxBoxes
      return i == $Trainer.party.length && !$Trainer.party_full? if box == -1
      return i < $PokemonStorage.maxPokemon(box) && $PokemonStorage[box, i].nil?
    end

    # the received Pokémon is gone: the one given comes back to its slot or any free place
    def self.give_back(gave, loc)
      if free?(*loc) then $PokemonStorage[*loc] = gave
      elsif !pbAddPokemonSilent(gave)
        log("no room to give #{gave.species} back")
        KIF::Net.notes << _INTL("No room to give {1} back. Make room and connect again.", gave.name)
        return false
      end
      return true
    end

    # a Pokédex entry only the undone trade made
    def self.dex_back(snap)
      sp, seen, owned = snap
      return if sp.nil? || (seen && owned) || stored.any? { |q, _| q.species == sp }
      d = $Trainer.pokedex
      n = getDexNumberForSpecies(sp)
      { seen: seen, owned: owned }.each do |kind, was|
        next if was
        if d.isTripleFusion(n) then d.instance_variable_get(:"@#{kind}_triple").delete(GameData::Species.try_get(sp)&.species)
        elsif d.isFusion(n) then b = getBodyID(sp); d.instance_variable_get(:"@#{kind}_fusion")[getHeadID(sp, b)][b] = false
        else d.instance_variable_get(:"@#{kind}_standard")[n] = false
        end
      end
      d.refresh_accessible_dexes
    rescue StandardError => e
      log("Pokédex not restored (#{e.class}: #{e.message})")
    end

    # the partner's game never swapped: the received Pokémon goes, the given one comes back.
    # Only for the partner the trade was made with, only while the received one is unchanged.
    def self.undo(id)
      e = book[id]
      return unless e.is_a?(Array)
      _, gave, loc, tag, who, fp, t0, dex = e
      return unless who == partner   # a name, not a key: a legacy or foreign entry is left alone
      if !tag.is_a?(String) || Time.now.to_i - t0.to_i > EXPIRE
        book[id] = :done
        return log("#{id}: too old to undo")
      end
      hits = stored.select { |q, _| [q, q.original_head, q.original_body].any? { |h| h.is_a?(Pokemon) && h.instance_variable_get(:@kif_trade_tag) == tag } }
      own = hits.select { |q, _| q.instance_variable_get(:@kif_trade_tag) == tag }
      if hits.empty?
        return unless give_back(gave, loc)   # no room: the entry stays for the next connection
      elsif hits.length == 1 && own.length == 1 && fingerprint(own[0][0]) == fp
        $PokemonStorage[*own[0][1]] = gave
      else   # changed, fused or copied since: the player keeps what came
        book[id] = :done
        KIF::Net.notes << _INTL("The trade with {1} didn't finish on their side. You keep the Pokemon you got.", partner)
        return log("#{id}: not undone (the received one was changed)")
      end
      book.delete(id)
      dex_back(dex)
      trades(-1)
      log("#{id}: undone (#{hits.empty? ? 'received one not found' : 'received one taken back'})")
      KIF::Net.notes << _INTL("The trade with {1} didn't finish on their side. {2} is back with you.", partner, gave.name)
    end

    # the partner's list of trade ids: pending ones it knows are final; the others it doesn't
    # know are undone (a list that is full may have been cut, so it proves nothing)
    def self.sync(text)
      return unless text =~ /\A(\h{8})*\z/
      theirs = text.scan(/\h{8}/).map { |h| h.to_i(16) }
      book.keys.each do |id|
        e = book[id]
        next unless e.is_a?(Array)
        if theirs.include?(id)
          book[id] = :done if e[4] == partner
        elsif theirs.length < LIST
          undo(id)
        end
      end
    end

    # Messages from the partner's game (KIF::Net.update)
    def self.receive(type, msg)
      id = msg["id"]
      if $game_temp&.in_battle && (type == "tr_sync" || (type == "tr_no" && book[id].is_a?(Array)))
        l = line[:later]   # the party stays as it is until the battle is over (map_tick)
        l << [type, msg] if l.length < 8
        return
      end
      case type
      when "tr_sync" then return sync(msg["ids"])
      when "tr_done"
        book[id] = :done if book[id].is_a?(Array) && book[id][4] == partner
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
        if !@st
          return if (m = line[:mute]) && KIF::Net.now < m   # asked and declined too often: a new question waits; the answer to this player's own ask doesn't
          @asked = id
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
      return unless allow?(st)
      case type
      when "tr_offer"
        d = msg["d"]
        st[:ok] = st[:their_ok] = false
        if KIF::Net::Wire.json(d).bytesize > MAX_OFFER   # not a Pokémon: not worked on, not kept
          st[:theirs] = st[:td] = nil
          st[:bad] = true
        else
          st[:theirs] = load(d)
          st[:td] = d
          st[:bad] = st[:theirs].nil?
        end
        log("#{id}: an offer that doesn't fit this game") if st[:bad]
      when "tr_ok", "tr_go"
        st[:their_ok] = st[:md] && st[:td] && msg["h"] == digest ? true : false
        if st[:ok] && st[:their_ok] && (type == "tr_go" || !st[:second])
          commit
          post("tr_go", "id" => id, "h" => msg["h"]) if st[:done] && type == "tr_ok"
        end
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

    # on the map: the partner asked (a question at a quiet moment), and what was held back
    # during a battle
    def self.map_tick
      l = line[:later]
      l.shift(l.length).each { |t, m| receive(t, m) } unless l.empty? || $game_temp&.in_battle
      return unless @asked && !@st && KIF::Net.quiet?
      id = @asked
      yes = pbConfirmMessage(_INTL("{1} wants to trade Pokémon. Trade now?", partner))
      return unless @asked == id && session
      return menu_pick if yes
      @asked = nil
      post("tr_no", "id" => id)
      ln = line   # two No answers: no more questions from this partner for a while
      ln[:declines] += 1
      ln[:mute] = KIF::Net.now + MUTE if ln[:declines] >= 2
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
      # Nuzlocke: not a dead Pokémon; Soul Link: not one linked to its pair (NSL-04)
      if defined?(KIF::Nuzlocke) && KIF::Nuzlocke.on? && !p.egg? && (p.hp <= 0 || p.kif_nz_dead)
        return pbMessage(_INTL("{1} is dead, so it can't be traded.", p.name))
      end
      if defined?(KIF::SoulLink) && (msg = KIF::SoulLink.leave_refusal(p, :trade))
        return pbMessage(msg)
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
        drawn = ready? ? digest : nil   # the pair on screen: a Confirm press counts for this one only
        r = m.pick(head, cmds, "", proc { [@st && @st[:v], session.nil?] })
        next if r.nil?
        a = r < 0 ? :cancel : acts[r]
        case a
        when :offer then choose
        when :summary
          pbFadeOutIn { PokemonSummaryScreen.new(PokemonSummary_Scene.new, true).pbStartScreen([st[:theirs]], 0, false) }
        when :confirm then pbMessage(_INTL("The offer changed. Look at it again.")) unless confirm(drawn)
        when :cancel
          cancel if @st && !@st[:done] && (!st[:mine] || pbConfirmMessage(_INTL("Stop trading?")))
        end
      end
    rescue StandardError => e   # a screen that can't draw what the partner sent ends the trade screen, not the game
      log("the trade screen stopped (#{e.class}: #{e.message})")
      (pbMessage(_INTL("The trade stopped. Check your Pokemon.")) rescue nil)
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
