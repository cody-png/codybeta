#===============================================================================
# F-NET-01 – Multiplayer: co-op battles, the partner's game (see NetCoop.rb)
#
# The battle runs in the other game. This game builds a copy of it for the
# battle screen only (never run): its own party as it is, the host's party and
# the foes from what the host sent, this player as the player (front left),
# the host as the partner. The host's log is played on this game's own battle
# scene (PIF's or EBDX's); its menus pick this player's moves, targets,
# switches, items and balls, checked against this game's own rules, and the
# host checks them again. HP and status come from the host, onto this
# player's own Pokémon, as they change, so a lost connection keeps what was
# seen. At the end: the final state, Exp with this game's own options (moves
# to learn are asked here), prize money, a Pokémon this player caught, items
# used, then the usual after-battle steps (Nuzlocke, Soul Link, evolutions,
# whiting out).
#===============================================================================
module KIF
  module Coop
    class Guest
      attr_reader :id, :mirror, :decision, :host_name, :party, :caught, :done
      attr_accessor :view

      def initialize(session, id, trainer, view = nil, bag: nil)
        @s = session
        @id = id
        @trainer = trainer
        @party = trainer.party.first(6)   # the Pokémon sent with co_join, in that order
        @bag = bag || (trainer.equal?($Trainer) ? $PokemonBag : nil)
        @view = view
        @host_name = session.partner.to_s
        @box = []
        @done = @begun = @started = @lost = false
        @caught = []
        # what this player picked: the end takes only these off its Bag and only
        # this many catches; Exp only for foes of this battle (finish)
        @picked = Hash.new(0)
        @balls = 0
        @foes = []
      end

      def feed(type, msg); @box << [type, msg] if msg.is_a?(Hash) && msg["id"] == @id; end
      def lost; @lost = true; end
      def lost?; @lost || !@s.connected?; end
      def session; @s; end

      # the host stopped waiting for this request (co_cmd or co_sw): its AI chose
      def skipped?(req); !skip_at(req).nil?; end

      # the host's battle ended meanwhile (its player ran away)
      def ended?; @box.any? { |t, _m| t == "co_end" }; end

      def skip_at(req)
        @box.index { |t, m| t == "co_skip" && m["d"].is_a?(Hash) && %w[b t n].all? { |k| m["d"][k] == req[k] } }
      end

      # true (and the note taken) when the host chose for this request
      def take_skip(req)
        KIF::Net.update if KIF::Net.session.equal?(@s)   # a Bag or party screen doesn't read the line
        i = skip_at(req) or return false
        @box.delete_at(i)
        @view.message(_INTL("{1}'s game chose for you this turn.", @host_name))
        return true
      end
      def started!; @started = true; end

      def int(v, lo, hi, d = nil); Mon.int(v, lo, hi, d); end

      #-------------------------------------------------------------------------
      # Places: the two player-side slots swap (this player is the player here)
      #-------------------------------------------------------------------------
      def bat(i); (i.is_a?(Integer) && i.even? && i <= 2) ? 2 - i : i; end

      # a host battler index -> this copy's, or nil
      def bat_checked(i)
        return nil unless @mirror && i.is_a?(Integer) && i >= 0 && i <= @mirror.maxBattlerIndex
        return bat(i)
      end

      def battler(i); (mi = bat_checked(i)) ? @mirror.battlers[mi] : nil; end

      # a host party index -> this copy's (side 0: this player's team first)
      def party_index(pi, side)
        return nil unless pi.is_a?(Integer) && pi >= 0
        return (pi < @mirror.pbParty(1).length ? pi : nil) if side == 1
        return nil if pi >= @hn + @gn
        return pi < @hn ? @gn + pi : pi - @hn
      end

      def own?(mp); mp.is_a?(Integer) && mp >= 0 && mp < @gn; end
      def own_pk?(pk); @party.any? { |x| x.equal?(pk) }; end

      #-------------------------------------------------------------------------
      # The host's messages, in order
      #-------------------------------------------------------------------------
      def step
        until @box.empty? || @done
          type = @box[0][0]
          break if !@started && type != "co_begin" && type != "co_end"
          type, msg = @box.shift
          begin
            handle(type, msg)
          rescue StandardError => e
            KIF::Coop.log("partner step failed on #{type} (#{e.class}: #{e.message})")
            reply_auto(type, msg)   # the host never waits on a failure here
          end
        end
      end

      def handle(type, msg)
        case type
        when "co_begin" then begin_battle(msg["d"]) unless @begun
        when "co_ev"    then (msg["e"] || []).each { |ev| @view.show(ev) if ev.is_a?(Array) }
        when "co_cmd"   then answer_command(msg["d"])
        when "co_sw"    then answer_switch(msg["d"])
        when "co_skip"  then @view.message(_INTL("{1}'s game chose for you this turn.", @host_name))   # this player's pick came too late
        when "co_end"   then finish(msg["d"])
        end
      end

      def reply_auto(type, msg)
        d = msg["d"].is_a?(Hash) ? msg["d"] : {}
        if type == "co_cmd"
          @s.post("co_act", "id" => @id, "d" => { "b" => d["b"], "t" => d["t"], "a" => "auto" })
        elsif type == "co_sw"
          @s.post("co_swr", "id" => @id, "d" => { "n" => d["n"], "p" => -2 })
        end
      end

      def begin_battle(d)
        @begun = true
        return if build(d)
        KIF::Coop.log("couldn't build #{@host_name}'s battle here; the game fights for this player")
        @mirror = nil
        @view = AutoView.new(self)
        @s.post("co_act", "id" => @id, "d" => { "b" => -1, "a" => "auto" })
      end

      def trainer_from(t)
        return nil unless t.is_a?(Hash)
        ty = Mon.sym(t["ty"], GameData::TrainerType) || ($Trainer.trainer_type rescue nil) || GameData::TrainerType.keys.first
        return NPCTrainer.new(Mon.name(t["n"]), ty)
      end

      # the battle as the host has it; false if what came doesn't fit
      def build(d)
        return false unless d.is_a?(Hash)
        sz = d["sz"]
        return false unless sz.is_a?(Array) && sz.length == 2 && sz[0] == 2 && sz[1].is_a?(Integer) && sz[1].between?(1, 3)
        @hn = int(d["gs"], 1, 6) or return false
        @gn = int(d["gn"], 1, 6) or return false
        return false unless @gn == @party.length && d["hp"].is_a?(Array) && d["hp"].length == @hn
        host_party = d["hp"].map { |h| Mon.load(h) }
        foes = d["fp"].is_a?(Array) && d["fp"].length.between?(1, 18) ? d["fp"].map { |h| Mon.load(h) } : []
        return false if foes.empty? || host_party.include?(nil) || foes.include?(nil)
        @foes = foes.map { |f| [f.species, f.level] }
        if d["lo"] == 1
          KIF::Coop.tell(:lost, _INTL("{1}'s game doesn't have some of your Pokémon's moves, Abilities or items (a mod's, or another KIF's), so there they fight without them.", @host_name))
        end
        wild = d["w"] == 1
        host = trainer_from(d["ht"]) or return false
        host.trainer_type = Mon.partner_type(d["ht"]["ty"])
        host.party = host_party
        opp = nil
        unless wild
          return false unless d["ft"].is_a?(Array) && d["ft"].length.between?(1, 3)
          opp = d["ft"].map { |t| trainer_from(t) }
          return false if opp.include?(nil)
        end
        fs = d["fs"]
        ok = fs.is_a?(Array) && fs.length == (opp ? opp.length : 1) && fs.all? { |x| x.is_a?(Integer) } &&
             fs[0] == 0 && fs.each_cons(2).all? { |a, b| a <= b } && fs.last < foes.length
        fs = [0] unless ok
        opp&.each_with_index { |t, i| t.party = foes[(fs[i] || 0)...(fs[i + 1] || foes.length)] }
        @view.make_scene if @view.respond_to?(:make_scene)
        m = PokeBattle_Battle.new(@view.scene, @party + host_party, foes, [@trainer, host], opp)
        m.party1starts = [0, @gn]
        m.party2starts = fs
        m.instance_variable_set(:@sideSizes, [2, sz[1]])
        m.backdrop = d["bd"] if d["bd"].is_a?(String) && d["bd"] =~ /\A[A-Za-z0-9_ ]{1,40}\z/
        m.backdrop = "Field" if m.backdrop.to_s.empty?
        m.backdropBase = d["bb"] if d["bb"].is_a?(String) && d["bb"] =~ /\A[A-Za-z0-9_ ]{1,40}\z/
        env = Mon.sym(d["env"], GameData::Environment)
        m.environment = env if env
        m.time = int(d["tm"], 0, 2, 0)
        m.internalBattle = true
        m.canLose = d["cl"] == 1
        m.canRun = d["cr"] == 1
        m.moneyGain = d["mg"] == 1
        m.expGain = d["eg"] == 1
        @mirror = m
        return false unless d["bt"].is_a?(Array)
        d["bt"].each do |e|
          next unless e.is_a?(Array) && e.length == 2
          mi = bat_checked(e[0]) or next
          mp = party_index(e[1], mi % 2) or next
          pk = m.pbParty(mi)[mp]
          next unless pk && !pk.egg? && m.battlers[mi].nil?
          m.pbCreateBattler(mi, pk, mp)
        end
        return false unless m.battlers[0] && own?(m.battlers[0].pokemonIndex)
        m.battlers.each { |b| m.pbSetSeen(b) if b && b.opposes? }
        nuzlocke_check(foes) if wild
        return true
      rescue StandardError => e
        KIF::Coop.log("battle setup failed (#{e.class}: #{e.message})")
        return false
      end

      # this player's own Nuzlocke judges its ball (the place may be used up here)
      def nuzlocke_check(foes)
        return unless defined?(KIF::Nuzlocke) && KIF::Nuzlocke.on? && @trainer.equal?($Trainer)
        place, verdict = KIF::Nuzlocke.judge(foes)
        @mirror.instance_variable_set(:@kif_nz, verdict)
        @mirror.instance_variable_set(:@kif_nz_place, place)
        @nz = [place, verdict]
      rescue StandardError => e
        KIF::Coop.log("Nuzlocke check failed (#{e.class}: #{e.message})")
      end

      # [index, hp, total, status, level] from the host, before each log entry
      def apply_snap(snap)
        return unless snap.is_a?(Array) && @mirror
        snap.each do |e|
          next unless e.is_a?(Array) && e.length >= 5
          b = battler(e[0]) or next
          pk = b.pokemon or next
          hp = int(e[1], 0, 99_999) or next
          if own_pk?(pk)
            pk.hp = hp if pk.hp != hp   # this game's own rules apply (No reviving)
          else
            th = int(e[2], 1, 99_999, b.totalhp)
            [b, pk].each { |o| o.instance_variable_set(:@totalhp, th) }
            pk.instance_variable_set(:@hp, [hp, th].min)
            lv = int(e[4], 1, GameData::GrowthRate.max_level)
            b.instance_variable_set(:@level, lv) if lv
          end
          b.instance_variable_set(:@hp, pk.hp)
          st = pk.hp > 0 ? (Mon.sym(e[3], GameData::Status) || :NONE) : :NONE
          [b, pk].each { |o| o.instance_variable_set(:@status, st) }
        end
      end

      # a sendout entry [host index, host party index, shown Pokémon] -> [index, Pokémon]
      def send_in(e)
        return nil unless e.is_a?(Array) && e.length >= 3
        mi = bat_checked(e[0]) or return nil
        mp = party_index(e[1], mi % 2) or return nil
        arr = @mirror.pbParty(mi)
        if mi.even? && own?(mp)
          pk = arr[mp]
          return nil unless pk && !pk.egg?
        else
          pk = Mon.load(e[2]) or return nil
          arr[mp] = pk
        end
        if @mirror.battlers[mi]
          @mirror.battlers[mi].pbInitialize(pk, mp)
        else
          @mirror.pbCreateBattler(mi, pk, mp)
        end
        return [mi, pk]
      end

      # HP, status and display order of this player's team (host's view)
      def sync_party(d)
        (d["pt"].is_a?(Array) ? d["pt"] : []).first(@gn).each_with_index do |x, j|
          pk = @party[j]
          next unless pk && x.is_a?(Array) && !@mirror.battlers.any? { |b| b && b.pokemon.equal?(pk) }
          hp = int(x[0], 0, pk.totalhp) or next
          pk.hp = hp if pk.hp != hp
          st = Mon.sym(x[1], GameData::Status)
          pk.instance_variable_set(:@status, st) if st && pk.hp > 0
        end
        o = d["ord"]
        if o.is_a?(Array) && o.length == @gn && o.sort == (0...@gn).to_a
          o.each_with_index { |v, j| @mirror.pbPartyOrder(0)[j] = v }
        end
      end

      # PP from the host (Transform and Mimic change the moves themselves)
      def sync_moves(b, mv)
        return unless mv.is_a?(Array) && mv.all? { |x| x.is_a?(Array) && x.length == 4 }
        ids = mv.map { |x| Mon.sym(x[0], GameData::Move) }
        return if ids.include?(nil) || ids.length > 4
        if ids != b.moves.map(&:id)
          b.moves = ids.map { |id| PokeBattle_Move.from_pokemon_move(@mirror, Pokemon::Move.new(id)) }
        end
        b.moves.each_with_index do |m, k|
          pp = int(mv[k][1], 0, 999, m.pp)
          m.pp = pp
          m.realMove.pp = pp if m.realMove && own_pk?(b.pokemon) && b.pokemon.moves.include?(m.realMove)
        end
      end

      def answer_command(d)
        return unless d.is_a?(Hash)
        mi = bat_checked(d["b"])
        b = mi && @mirror ? @mirror.battlers[mi] : nil
        @mirror.instance_variable_set(:@kif_log_turn, int(d["t"], 0, 9999, 0)) if @mirror   # Battle Log: lines from here on are this turn's
        a = nil
        if b && mi.even? && own_pk?(b.pokemon)
          sync_party(d)
          sync_moves(b, d["mv"])
          a = @view.command(mi, d) unless KIF::Coop.auto_battle?
        end
        return if take_skip(d) || ended?   # nothing to send: the host went on
        if a && a["a"] == "item"
          @picked[a["i"]] += 1
          @balls += 1 if (GameData::Item.get(a["i"].to_sym).is_poke_ball? rescue false)
        end
        a ||= { "a" => "auto" }
        @s.post("co_act", "id" => @id, "d" => a.merge("b" => d["b"], "t" => d["t"]))
        @view.waiting
      end

      def answer_switch(d)
        return unless d.is_a?(Hash)
        mi = bat_checked(d["b"])
        p = -2
        if mi && mi.even? && @mirror && !KIF::Coop.auto_battle?
          sync_party(d)
          p = @view.replacement(mi, d) || -2
        end
        return if take_skip(d) || ended?
        @s.post("co_swr", "id" => @id, "d" => { "n" => d["n"], "p" => p })
        @view.waiting
      end

      #-------------------------------------------------------------------------
      # The end
      #-------------------------------------------------------------------------
      def finish(d)
        @done = true
        d = {} unless d.is_a?(Hash)
        @decision = int(d["dc"], 0, 5, 0)
        KIF::Coop.log("#{@host_name}'s battle #{@id} over (#{d['x'] ? Mon.name(d['x']) : @decision})")   # the host logs its own end
        @can_lose = d["cl"] == 1
        if d["x"] || !@begun
          @aborted = true
          @decision = 0
          if d["x"] == "party"
            KIF::Coop.tell(:party, _INTL("{1}'s game doesn't have one of your Pokémon (a mod's, or another KIF's), so you didn't join the battle.", @host_name))
          end
          return
        end
        apply_final(d["pt"])
        return unless @mirror
        award_exp(d["k"]) if @mirror.expGain
        money
        store_catches(d["c"])
        use_items(d["it"])
      end

      def apply_final(pt)
        (pt.is_a?(Array) ? pt : []).first(@gn || @party.length).each_with_index do |x, j|
          pk = @party[j]
          next unless pk && x.is_a?(Array) && x.length == 4 && !pk.egg?
          hp = int(x[0], 0, pk.totalhp) or next
          pk.hp = hp if pk.hp != hp
          st = pk.hp > 0 ? (Mon.sym(x[1], GameData::Status) || :NONE) : :NONE
          pk.instance_variable_set(:@status, st)
          pk.statusCount = int(x[2], 0, 255, 0)
          (x[3].is_a?(Array) ? x[3] : []).each_with_index { |pp, k| pk.moves[k].pp = int(pp, 0, 999, pk.moves[k].pp) if pk.moves[k] }
        end
      end

      # each foe the host noted: this game's own pbGainExp, one foe at a time
      def award_exp(kills)
        return unless kills.is_a?(Array)
        keep = @mirror.battlers
        left = @foes.dup   # each foe of this battle once
        kills.first(left.length).each do |k|
          next unless k.is_a?(Hash)
          sp = Mon.sym(k["s"], GameData::Species) or next
          lv = int(k["l"], 1, GameData::GrowthRate.max_level) or next
          i = left.index([sp, lv]) or next
          left.delete_at(i)
          parts = (k["p"].is_a?(Array) ? k["p"] : []).map { |pi| party_index(pi, 0) }.compact.uniq
          next if parts.empty?
          foe = Pokemon.new(sp, lv, nil, false, false)
          foe.instance_variable_set(:@hp, 0)
          fake = PokeBattle_Battler.new(@mirror, 1)
          fake.pbInitialize(foe, 0)
          fake.participants = parts
          list = Array.new(keep.length)
          keep.each_with_index { |b, i| list[i] = b if b && i.even? }
          list[1] = fake
          @mirror.instance_variable_set(:@battlers, list)
          begin
            @mirror.pbGainExp
          rescue StandardError => e
            KIF::Coop.log("Exp not given (#{e.class}: #{e.message})")
          ensure
            @mirror.instance_variable_set(:@battlers, keep)
          end
        end
      end

      def money
        if @decision == 1 && @mirror.trainerBattle?
          @mirror.pbGainMoney
        elsif @decision == 2 || @decision == 5
          @mirror.pbLoseMoney
        end
      rescue StandardError => e
        KIF::Coop.log("money step failed (#{e.class}: #{e.message})")
      end

      def store_catches(list)
        return unless list.is_a?(Array) && !list.empty?
        # no more than this player's balls, and only foes of this battle
        pks = list.first([@balls, 6].min).map { |h| Mon.load(h, true) }.compact.select { |pk| @foes.any? { |s, _| s == pk.species } }
        pks.each do |pk|
          pk.reset_moves if pk.instance_variable_defined?(:@kif_coop_slots)   # a move this game lacks: its own level-up moves, not Struggle
          [:@kif_coop_slots, :@kif_coop_lost].each { |v| pk.remove_instance_variable(v) if pk.instance_variable_defined?(v) }
          pk.owner = Pokemon::Owner.new_from_trainer(@trainer)
          pk.obtain_map = $game_map.map_id if $game_map
          KIF::NetSprite.forget(pk) if defined?(KIF::NetSprite)
        end
        @caught = pks
        @mirror.instance_variable_get(:@caughtPokemon).concat(pks)
        @mirror.pbRecordAndStoreCaughtPokemon
      rescue StandardError => e
        KIF::Coop.log("catch not stored (#{e.class}: #{e.message})")
      end

      def use_items(list)
        return unless @bag && list.is_a?(Array)
        list.first(20).each do |x|
          next unless x.is_a?(Array) && x.length == 2
          it = Mon.sym(x[0], GameData::Item) or next
          n = [int(x[1], 1, 99) || 0, @picked[it.to_s]].min   # never more than this player picked
          @bag.pbDeleteItem(it, n) if n > 0
        end
      end

      #-------------------------------------------------------------------------
      # The whole battle, from this game's map
      #-------------------------------------------------------------------------
      def run
        @view ||= SceneView.new(self)
        t0 = KIF::Net.now
        until @begun || @done
          if lost? || KIF::Net.now - t0 > KIF::Coop.begin_wait
            KIF::Coop.log("#{@host_name}'s battle didn't start here")
            return
          end
          Graphics.update
          Input.update
          KIF::Net.update
          step
        end
        return if @done && !@mirror
        Events.onStartBattle.trigger(nil)   # levels before, for the evolution check after
        if @mirror
          wild = @mirror.wildBattle?
          bgm = wild ? pbGetWildBattleBGM(@mirror.pbParty(1)) : pbGetTrainerBattleBGM(@mirror.opponent)
          type = wild ? (@mirror.pbParty(1).length == 1 ? 0 : 2) : 3
          pbBattleAnimation(bgm, type, wild ? @mirror.pbParty(1) : @mirror.opponent) {
            pbSceneStandby { play }
            after_battle
          }
        else
          play
          after_battle
        end
        Input.update
      end

      def play
        begin
          @view.start
        rescue StandardError => e
          KIF::Coop.log("battle screen failed (#{e.class}: #{e.message})")
          (@view.finish(0) rescue nil)
          if !@plain && defined?(PokeBattle_SceneEBDX) && @view.scene.is_a?(PokeBattle_SceneEBDX)
            @plain = true   # EBDX's screen failed: PIF's own
            @view = SceneView.new(self, PokeBattle_Scene.new)
            @mirror.instance_variable_set(:@scene, @view.scene)
            retry
          end
          @view = AutoView.new(self)
          @mirror&.instance_variable_set(:@scene, @view.scene)
          @s.post("co_act", "id" => @id, "d" => { "b" => -1, "a" => "auto" })
          @view.start
        end
        started!
        until @done
          if lost?
            @view.message(_INTL("Lost the connection to {1}. Your Pokémon keep the HP they had.", @host_name))
            break
          end
          @view.frame
          KIF::Net.update
          step
        end
        @view.finish(@decision || 0)
      end

      def after_battle
        if !@caught.empty? && @nz && @nz[1] == :first && KIF::Nuzlocke.on?
          KIF::Nuzlocke.pending = [@nz[0], @mirror.pbParty(1).compact]   # this player's catch uses up the place
        end
        d = @decision || 0
        pbAfterBattle(d, @can_lose || d == 0 || @aborted ? true : false)
      end
    end

    #---------------------------------------------------------------------------
    # The battle on this game's own battle scene
    #---------------------------------------------------------------------------
    class SceneView
      attr_reader :scene

      def initialize(guest, scene = nil)
        @g = guest
        @scene = scene
        @warned = {}
      end

      def make_scene; @scene ||= pbNewBattleScene; end

      def start
        @scene.extend(MenuWatch) unless @scene.is_a?(MenuWatch)
        @scene.instance_variable_set(:@kif_coop_view, self)
        @scene.pbStartBattle(@g.mirror)
      end
      def finish(decision); call(:pbEndBattle, decision); end
      def waiting; call(:pbDisplayMessage, _INTL("Waiting for {1}...", @g.host_name), true); end
      def message(t); call(:pbDisplayPausedMessage, t); end
      def int(v, lo, hi, d = nil); Mon.int(v, lo, hi, d); end

      def frame
        if @scene.class.method_defined?(:pbUpdate)
          @scene.pbUpdate
        else
          Graphics.update
          Input.update
        end
      end

      # a scene method from this file's own list, with as many arguments as it takes
      def call(m, *args, &blk)
        return nil unless @scene.respond_to?(m)
        prm = @scene.method(m).parameters
        args = args.first(prm.count { |t, _| t == :req || t == :opt }) unless prm.any? { |t, _| t == :rest }
        return @scene.send(m, *args, &blk)
      rescue StandardError => e
        KIF::Coop.log("couldn't show #{m} (#{e.class}: #{e.message})") unless @warned[m]
        @warned[m] = true
        return nil
      end

      # PIF: (battler, secondAbility, abilityName); EBDX: (battler, delay, logTrigger, abilityName)
      def ability(b, second, name)
        prm = (@scene.method(:pbShowAbilitySplash).parameters.map(&:last) rescue [])
        at = prm.index(:abilityName)
        return call(:pbShowAbilitySplash, b, second, name) unless at
        args = Array.new(at + 1) { |k| k == 0 ? b : k == at ? name : (k == 1 && prm[1] == :secondAbility ? second : k == 1 ? false : true) }
        call(:pbShowAbilitySplash, *args)
      end

      # The host's text, worded for this player: the host calls this player's
      # Pokémon "the ally ..." and its own by name; here it's the other way
      # round, and the send-out line names the host as the trainer.
      def mine(t)
        t = Mon.text(t)
        m = @g.mirror or return t
        own, host = m.battlers.select { |b| b && b.index.even? }.partition { |b| @g.own_pk?(b.pokemon) }.map { |l| l.map(&:name) }
        return sent_out(t, own, host) || t.split("\n", -1).map { |line| ally_line(line, own, host) }.join("\n")
      end

      # "<this player> sent out A!\nGo! B!" -> "<host> sent out B!\nGo! A!", or nil
      def sent_out(t, own, host)
        a, b = t.split("\n")
        return nil unless own.length == 1 && host.length == 1 && t.count("\n") == 1 && b == _INTL("Go! {1}!", host[0])
        pat = Regexp.escape(_INTL("{1} sent out {2}!", "KIFAAA", "KIFBBB")).sub("KIFAAA", ".+").sub("KIFBBB") { Regexp.escape(own[0]) }
        return nil unless a =~ /\A#{pat}\z/
        who = (@g.mirror.player[1].full_name rescue @g.host_name)
        return _INTL("{1} sent out {2}!", who, host[0]) + "\n" + _INTL("Go! {1}!", own[0])
      end

      # (one pass at the start, so a host's and this player's Pokémon with the same name stay apart)
      def ally_line(line, own, host)
        own.each { |x| line = line.gsub(_INTL("the ally {1}", x), x) }
        n = own.find { |x| line.start_with?(_INTL("The ally {1}", x)) }
        return n + line[_INTL("The ally {1}", n).length..-1] if n
        n = host.find { |x| line =~ /\A#{Regexp.escape(x)}[ ']/ }   # "Squirtle used", "Squirtle's" (not "Squirtle, come back!")
        return n ? _INTL("The ally {1}", n) + line[n.length..-1] : line
      end

      def show(ev)
        type, args, snap = ev
        return unless type.is_a?(String) && args.is_a?(Array)
        g = @g
        g.apply_snap(snap)
        case type
        when "m", "mp"
          t = mine(args[0])
          KIF::BattleLog.add(g.mirror, t) if defined?(KIF::BattleLog) && g.mirror   # this player's Battle Info Log page
          type == "m" ? call(:pbDisplayMessage, t, args[1] == 1) : call(:pbDisplayPausedMessage, t)
        when "so"
          list = (args[0].is_a?(Array) ? args[0] : []).map { |e| g.send_in(e) }.compact
          call(:pbSendOutBattlers, list, args[1] == 1) unless list.empty?
        when "rc" then (b = g.battler(args[0])) && call(:pbRecall, b.index)
        when "hp" then (b = g.battler(args[0])) && call(:pbHPChanged, b, int(args[1], 0, 99_999, b.hp), args[2] == 1)
        when "da" then (b = g.battler(args[0])) && call(:pbDamageAnimation, b, int(args[1], 0, 16, 0))
        when "hl"
          t = (args[0].is_a?(Array) ? args[0] : []).map do |x|
            b = x.is_a?(Array) ? g.battler(x[0]) : nil
            b ? [b, int(x[1], 0, 99_999, b.hp), int(x[2], 0, 16, 0)] : nil
          end.compact
          call(:pbHitAndHPLossAnimation, t) unless t.empty?
        when "fa" then (b = g.battler(args[0])) && call(:pbFaintBattler, b)
        when "an"
          mv = Mon.sym(args[0], GameData::Move)
          u = g.battler(args[1])
          ts = (args[2].is_a?(Array) ? args[2] : []).map { |x| g.battler(x) }.compact
          call(:pbAnimation, mv, u, ts, int(args[3], 0, 20, 0)) if mv && u
        when "ca"
          name = args[0].is_a?(String) && args[0] =~ /\A[A-Za-z0-9]{1,32}\z/ ? args[0] : nil
          call(:pbCommonAnimation, name, g.battler(args[1]), g.battler(args[2])) if name
        when "ab"
          if (b = g.battler(args[0]))
            KIF::BattleLog.popup(g.mirror, b, Mon.name(args[2])) if defined?(KIF::BattleLog)
            ability(b, args[1] == 1, Mon.name(args[2]))
          end
        when "abh" then (b = g.battler(args[0])) && call(:pbHideAbilitySplash, b)
        when "ch"  then (b = g.battler(args[0])) && (pk = Mon.load(args[1])) && call(:pbChangePokemon, b.index, pk)
        when "rf"  then call(:pbRefresh)
        when "r1"  then (b = g.battler(args[0])) && call(:pbRefreshOne, b.index)
        when "op"  then call(:pbShowOpponent, int(args[0], 0, 2, 0))
        when "pl"  then call(:pbShowPartyLineup, int(args[0], 0, 1, 0), args[1] == 1)
        when "th"
          b = g.battler(args[3])
          ball = Mon.sym(args[0], GameData::Item)
          call(:pbThrow, ball, int(args[1], 0, 4, 0), args[2] == 1, b.index, args[4] == 1) if b && ball
        when "ts"  then call(:pbThrowSuccess)
        when "hc"  then (b = g.battler(args[0])) && call(:pbHideCaptureBall, b.index)
        when "td"
          b = g.battler(args[1])
          ball = Mon.sym(args[0], GameData::Item)
          call(:pbThrowAndDeflect, ball, b.index) if b && ball
        when "ws"  then call(:pbWildBattleSuccess)
        when "tw"  then call(:pbTrainerBattleSuccess)
        end
      end

      #-------------------------------------------------------------------------
      # This player's choices, on this game's menus. nil: the host's AI picks.
      # While a menu is up the line is read each frame (MenuWatch): an invite
      # is answered "busy", and when the host chose for this request the
      # command menu closes.
      #-------------------------------------------------------------------------
      def menu(req)
        @asking = req
        cw = catch(:kif_coop_skip) { return yield }
        @asking = nil   # before the hide animation's own frames
        cw.hidePlay if cw.respond_to?(:hidePlay)   # EBDX's command window slides out
        call(:pbSelectBattler, -1)
        return nil
      ensure
        @asking = nil
      end

      # each frame of this game's battle scene (MenuWatch)
      def menu_frame(cw)
        req = @asking
        return unless req && !@polling
        begin
          @polling = true
          KIF::Net.update if KIF::Net.session.equal?(@g.session)
        ensure
          @polling = false
        end
        throw :kif_coop_skip, cw if command_window?(cw) && (@g.skipped?(req) || @g.ended? || @g.lost?)
      end

      # only the command menu closes early: a fight, Bag or party screen ends as usual (then the note shows)
      def command_window?(cw)
        return false unless cw
        sp = @scene.instance_variable_get(:@sprites)
        return cw.equal?(@scene.instance_variable_get(:@commandWindow)) || (sp.respond_to?(:[]) && cw.equal?(sp["commandWindow"]))
      end

      def command(mi, req); menu(req) { pick_command(mi, req) }; end

      def pick_command(mi, req)
        m = @g.mirror
        b = m.battlers[mi]
        200.times do
          cmd = call(:pbCommandMenu, mi, true)
          return nil unless cmd.is_a?(Integer)
          case cmd
          when 0
            return { "a" => "move", "m" => -1 } if req["fa"] == 1   # Encore, or no PP left: the battle picks
            a = fight(mi, b, req)
            return a if a
          when 1
            a = bag(mi, b)
            return a if a
          when 2
            if req["sw"] != 1
              call(:pbDisplayPausedMessage, _INTL("{1} can't be switched out!", b.name))
              next
            end
            p = party(mi, true)
            return { "a" => "switch", "p" => p } if p
          when 3
            if m.trainerBattle?
              call(:pbDisplayPausedMessage, _INTL("No! There's no running from a Trainer battle!"))
            elsif req["rn"] != 1
              call(:pbDisplayPausedMessage, _INTL("You can't escape!"))
            else
              return { "a" => "run" }
            end
          end
        end
        return nil
      end

      def fight(mi, b, req)
        usable = req["mv"].is_a?(Array) ? req["mv"].map { |x| x.is_a?(Array) && x[3] == 1 } : []
        ret = nil
        call(:pbFightMenu, mi, false) do |k|
          next true if k == -1
          next false unless k.is_a?(Integer) && k >= 0 && b.moves[k] && b.moves[k].id
          unless usable[k]
            call(:pbDisplayPausedMessage, _INTL("{1} can't use that move right now.", b.name))
            next false
          end
          tg = -1
          unless @g.mirror.singleBattle?
            t = call(:pbChooseTarget, mi, b.moves[k].pbTarget(b))
            next false unless t.is_a?(Integer) && t >= 0
            tg = @g.bat(t)
          end
          ret = { "a" => "move", "m" => k, "tg" => tg }
          next true
        end
        return ret
      end

      def bag(mi, b)
        m = @g.mirror
        ret = nil
        call(:pbItemMenu, mi, true) do |item, use, ip, im, isc|
          next false unless item
          pk = bt = nil
          case use
          when 1, 2, 6, 7
            next false unless ItemHandlers.hasBattleUseOnPokemon(item) && @g.own?(ip)
            pk = m.pbParty(mi)[ip]
            bt = m.pbFindBattler(ip, mi)
          when 3, 8
            next false unless ItemHandlers.hasBattleUseOnBattler(item) && @g.own?(ip)
            bt = m.pbFindBattler(ip, mi)
            pk = bt.pokemon if bt
          when 4, 9
            next false unless ip.is_a?(Integer) && ip >= 0
            bt = m.battlers[ip]
            pk = bt.pokemon if bt
          when 5, 10
            bt = b
            pk = b.pokemon
          else
            next false
          end
          next false unless pk
          next false if [1, 2, 3, 6, 7, 8].include?(use) && !m.pbCanUseItemOnPokemon?(item, pk, bt, isc)
          next false unless ItemHandlers.triggerCanUseInBattle(item, pk, bt, im, true, m, isc)
          ret = { "a" => "item", "i" => item.to_s, "p" => ip, "mv" => im }
          ret["tb"] = @g.bat(ip) if [4, 9].include?(use)
          next true
        end
        return ret
      end

      # a party slot of this player's team, or nil
      def party(mi, cancel)
        m = @g.mirror
        ret = nil
        call(:pbPartyScreen, mi, cancel) do |ip, psc|
          pk = ip.is_a?(Integer) && @g.own?(ip) ? m.pbParty(mi)[ip] : nil
          next false unless pk
          if !pk.able?
            (psc.pbDisplay(_INTL("{1} has no energy left to battle!", pk.name)) rescue nil)
            next false
          end
          if m.pbFindBattler(ip, mi)
            (psc.pbDisplay(_INTL("{1} is already in battle!", pk.name)) rescue nil)
            next false
          end
          ret = ip
          next true
        end
        return ret
      end

      def replacement(mi, req)
        p = menu(req) { party(mi, req["c"] == 1) }
        return p if p
        return req["c"] == 1 ? -1 : -2
      end
    end

    # on the partner's battle scene object only (SceneView#start)
    module MenuWatch
      def pbUpdate(*args)
        super
        v = @kif_coop_view
        v.menu_frame(args[0]) if v
      end
    end

    #---------------------------------------------------------------------------
    # When this game can't show the battle: the host's AI fights for this
    # player; what happens at the end shows as messages on the map
    #---------------------------------------------------------------------------
    class AutoScene < PokeBattle_DebugSceneNoLogging
      def pbDisplayMessage(msg, brief = false); pbMessage(msg) unless brief; end
      def pbDisplayPausedMessage(msg); pbMessage(msg); end
      def pbDisplayConfirmMessage(msg); return pbConfirmMessage(msg); end
      def pbShowCommands(msg, commands, defaultValue); return pbMessage(msg, commands, defaultValue); end

      def pbForgetMove(pkmn, moveToLearn)
        ret = -1
        pbFadeOutIn {
          scene = PokemonSummary_Scene.new
          screen = PokemonSummaryScreen.new(scene)
          ret = screen.pbStartForgetScreen([pkmn], 0, moveToLearn)
        }
        return ret
      end

      def pbNameEntry(helpText, pkmn); return pbEnterPokemonName(helpText, 0, Pokemon::MAX_NAME_SIZE, "", pkmn); end
      def pbShowPokedex(_pkmn); end
    end

    class AutoView
      attr_reader :scene

      def initialize(guest)
        @g = guest
        @scene = AutoScene.new
      end

      def make_scene; @scene; end
      def start; pbMessage(_INTL("This game couldn't show {1}'s battle. The game fights for your Pokémon there.", @g.host_name)); end
      def finish(_d); end
      def frame; Graphics.update; Input.update; end
      def waiting; end
      def message(t); pbMessage(t); end
      def show(_ev); end
      def command(_mi, _req); nil; end
      def replacement(_mi, _req); -2; end
    end
  end
end
