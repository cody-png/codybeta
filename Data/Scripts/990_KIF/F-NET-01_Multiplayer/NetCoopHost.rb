#===============================================================================
# F-NET-01 – Multiplayer: co-op battles, the game that runs the battle
# (see NetCoop.rb)
#
# A battle that starts here while Fight together is on asks the partner
# (co_ask). If their game joins, the partner's party (rebuilt from checked
# fields) becomes PIF's partner trainer for this battle only
# ($PokemonGlobal.partner, as in PIF's story partner battles) and the battle
# is a double: 2v1 against one wild Pokémon or a trainer with one, 2v2
# otherwise (a trainer sends out two at once). The battle runs here as usual,
# with these additions while it lasts:
#   * the partner's battler is commanded by the partner (co_cmd / co_act),
#     sent its replacement (co_sw / co_swr); a choice that doesn't fit, no
#     answer in time (B stops waiting) or a lost connection: PIF's AI picks;
#   * what the battle scene shows goes to the partner as a log (co_ev);
#   * foes the partner's Pokémon fought are noted for its Exp (its own game
#     works the Exp out, with its own options); a Pokémon the partner's ball
#     caught goes to the partner, not here; items it used come off its Bag;
#   * PIF heals both teams after a partner battle; a co-op battle doesn't.
# Exp is the partner's at the end of the battle; levels gained show then.
#===============================================================================
module KIF
  module Coop
    @hosting = false
    @pending_host = nil

    class << self
      attr_reader :pending_host
    end

    def self.hosting?; @hosting; end

    # a battle starting here may ask the partner
    def self.may_host?
      return false unless on? && !@hosting && !@guest
      return false if $PokemonGlobal.nil? || $PokemonGlobal.partner
      r = $PokemonTemp.battleRules
      return false if r["noPartner"] || r["birdboss"]
      return false if r["size"] && !%w[double 2v2 2v1].include?(r["size"])
      return false if (pbInSafari? rescue false) || (pbInBugContest? rescue false)
      return false if defined?(KIF::SelfBattle) && KIF::SelfBattle.instance_variable_get(:@active)
      return false if ($Trainer.able_pokemon_count rescue 0) == 0
      return false if ($game_switches[SWITCH_TRIPLE_BOSS_BATTLE] rescue false)
      return true
    end

    # wild Pokémon in pbWildBattleCore's arguments
    def self.count_wild(args)
      n = 0
      half = false
      args.each do |a|
        if a.is_a?(Pokemon) || a.is_a?(Array) then n += 1
        elsif half then n += 1; half = false
        else half = true
        end
      end
      return n
    end

    def self.host_battle(kind, nfoes)
      join = invite(kind)
      return yield unless join
      s = session
      return yield unless s
      @hosting = true
      host = Host.new(s, join)
      old = $PokemonGlobal.partner
      if !$PokemonTemp.battleRules["size"] && (kind == :trainer || nfoes == 1)
        setBattleRule("2v1")   # room for the partner; 2v2 once a trainer's party is known
        host.mine_size = true
      end
      $PokemonGlobal.partner = [join[:type], join[:name], join[:tid], join[:party]]
      @pending_host = host
      log("battle #{join[:id]} with #{join[:name]} (#{kind})")
      begin
        return yield
      ensure
        $PokemonGlobal.partner = old
        @pending_host = nil
        @hosting = false
        (host.finish(0, "abort") rescue nil)
      end
    end

    # pbPrepareBattle: the battle exists; the partner is in it if PIF added them
    def self.prepare(battle)
      h = @pending_host or return
      @pending_host = nil
      return unless battle.player && battle.player.length == 2 && battle.pbPartyStarts(0).length == 2
      if h.mine_size
        foes = battle.pbParty(1).count { |p| p && p.able? }
        battle.setBattleMode(battle.trainerBattle? && foes >= 2 ? "double" : "2v1")
      end
      h.attach(battle)
    end

    #---------------------------------------------------------------------------
    # One co-op battle, on the game that runs it
    #---------------------------------------------------------------------------
    class Host
      attr_reader :id, :name, :battle, :lost, :kills, :caught, :items
      attr_accessor :mine_size

      def initialize(session, join)
        @s = session
        @join = join
        @id = join[:id]
        @name = join[:name]
        @buf = []
        @quiet = 0
        @kills = []
        @caught = []
        @items = Hash.new(0)
        @pending = {}
        @answers = {}
        @turn = 0
        @swn = 0
        @lost = false
        @done = false
      end

      def attach(battle)
        @battle = battle
        battle.instance_variable_set(:@kif_coop, self)
        sc = battle.scene
        sc.extend(KIF::Coop::Capture)
        sc.instance_variable_set(:@kif_coop, self)
      end

      def start; @battle.pbPartyStarts(0)[1]; end
      def guest_party; @battle.pbParty(0)[start..-1] || []; end
      def slot?(abs); abs.is_a?(Integer) && abs >= start && abs < @battle.pbParty(0).length; end

      def guest?(idx)
        return false unless idx.is_a?(Integer) && @battle && @battle.battlers[idx] && !@battle.opposes?(idx)
        return @battle.pbGetOwnerIndexFromBattlerIndex(idx) == 1
      end

      def quiet?; @quiet > 0; end

      def quietly
        @quiet += 1
        return yield
      ensure
        @quiet -= 1
      end

      def post(type, fields)
        return false unless connected?
        @s.post(type, fields.merge("id" => @id))
      end

      def connected?
        return false if @lost
        return true if @s.connected?
        lose
        return false
      end

      def lose
        return if @lost
        @lost = true
        KIF::Coop.log("lost #{@name} during the battle")
        return unless @battle && !@done
        quietly { @battle.pbDisplayPaused(_INTL("Lost the connection to {1}. The game fights for {1}'s Pokémon now.", @name)) }
      rescue StandardError
        nil
      end

      #-------------------------------------------------------------------------
      # The log
      #-------------------------------------------------------------------------
      # [index, hp, total hp, status, level] of every battler
      def snap
        @battle.battlers.each_with_index.map { |b, i| b ? [i, b.hp, b.totalhp, b.status.to_s, b.level] : nil }.compact
      end

      def push(type, args)
        return if @lost || @done
        last = @buf.last
        if type == "r1" && last && last[0] == "r1" && last[1] == args
          last[2] = snap   # the same box drawn again
          return
        end
        @buf << [type, args, snap]
        flush if type == "m" || type == "mp" || @buf.length >= 24
      end

      def flush
        KIF::Net.update if KIF::Net.session.equal?(@s)   # notices a closed line
        return if @buf.empty?
        post("co_ev", "e" => @buf) if connected?
        @buf = []
      end

      def disp(p); p ? KIF::Coop::Mon.dump(p) : nil; end

      def trainer_h(t); { "n" => t.name.to_s[0, 24], "ty" => t.trainer_type.to_s[0, 48] }; end

      # the battle scene starts: everything the partner's game needs to show it
      def begin_battle
        b = @battle
        d = { "w" => b.wildBattle? ? 1 : 0, "sz" => [b.pbSideSize(0), b.pbSideSize(1)],
              "env" => b.environment.to_s, "bd" => b.backdrop.to_s, "bb" => b.backdropBase.to_s, "tm" => b.time.to_i,
              "ht" => trainer_h(b.player[0]), "hp" => b.pbParty(0)[0...start].map { |p| disp(p) },
              "gs" => start, "gn" => guest_party.length,
              "ft" => (b.opponent || []).map { |t| trainer_h(t) }, "fp" => b.pbParty(1).map { |p| disp(p) },
              "fs" => b.pbPartyStarts(1),
              "bt" => b.battlers.each_with_index.map { |x, i| x ? [i, x.pokemonIndex] : nil }.compact,
              "cl" => b.canLose ? 1 : 0, "cr" => b.canRun ? 1 : 0, "mg" => b.moneyGain ? 1 : 0, "eg" => b.expGain ? 1 : 0 }
        post("co_begin", "d" => d)
      end

      #-------------------------------------------------------------------------
      # Waiting for the partner: the battle scene keeps moving
      #-------------------------------------------------------------------------
      def frame
        sc = @battle.scene
        if sc.class.method_defined?(:pbUpdate)
          sc.pbUpdate
        else
          Graphics.update
          Input.update
        end
      rescue StandardError
        Graphics.update
        Input.update
      end

      # true once the block is; false: time up, B pressed, or the line is gone
      def wait(secs, label)
        t0 = KIF::Net.now
        shown = false
        loop do
          KIF::Net.update if KIF::Net.session.equal?(@s)
          return true if yield
          return false unless connected?
          return false if KIF::Net.now - t0 > secs
          if label && !shown && KIF::Net.now - t0 > 0.3
            shown = true
            (quietly { @battle.pbDisplayBrief(label) } rescue nil)
          end
          frame
          return false if Input.trigger?(Input::BACK)
        end
      end

      def wait_text; _INTL("Waiting for {1}... (B: the game picks)", @name); end

      #-------------------------------------------------------------------------
      # Turns
      #-------------------------------------------------------------------------
      def order
        o = @battle.pbPartyOrder(0)
        return guest_party.each_index.map { |j| (o[start + j] || start + j) - start }
      end

      def party_state
        guest_party.map { |p| p ? [p.hp, p.status.to_s] : nil }
      end

      def request(i)
        b = @battle.battlers[i]
        mv = b.moves.each_with_index.map do |m, j|
          [m.id.to_s, m.pp.to_i, m.total_pp.to_i, @battle.pbCanChooseMove?(i, j, false) ? 1 : 0]
        end
        return { "b" => i, "t" => @turn, "mv" => mv, "fa" => @battle.pbCanShowFightMenu?(i) ? 0 : 1,
                 "sw" => @battle.pbCanSwitch?(i) ? 1 : 0, "rn" => (@battle.wildBattle? && @battle.pbCanRun?(i)) ? 1 : 0,
                 "ord" => order, "pt" => party_state }
      end

      # the command phase starts: the partner chooses while this player does
      def ask_commands
        @pending = {}
        @answers = {}
        return unless connected? && !@auto
        @turn += 1
        @battle.battlers.each_with_index do |b, i|
          next unless b && guest?(i)
          next unless @battle.choices[i][0] == :None && @battle.pbCanShowCommands?(i)
          @pending[i] = @turn
          flush
          post("co_cmd", "d" => request(i))
        end
      end

      def collect
        while (r = KIF::Coop.take_host(@id, ["co_act"]))
          d = r[1]["d"]
          if d["b"] == -1 && d["a"] == "auto"
            @auto = true   # the partner's game can't show the battle: the AI fights for it
            next
          end
          @answers[d["b"]] = d if @pending[d["b"]] && d["t"] == @pending[d["b"]]
        end
        return @auto || @pending.keys.all? { |i| @answers[i] }
      end

      # before the AI chooses: the partner's choices, or none (the AI picks)
      def take_commands
        return if @pending.empty?
        if connected? && !@auto
          flush
          unless wait(KIF::Coop.cmd_wait, wait_text) { collect }
            KIF::Coop.log("no choice from #{@name} for turn #{@turn}") unless @lost
          end
        end
        @pending.each_key do |i|
          a = @answers[i]
          next unless a
          ok = begin
                 apply(i, a)
               rescue StandardError => e
                 KIF::Coop.log("#{@name}'s choice failed (#{e.class}: #{e.message})")
                 false
               end
          @battle.pbClearChoice(i) unless ok || @battle.choices[i][0] == :None
          break if @battle.decision != 0
        end
        @pending = {}
      end

      def int(v, lo, hi, d = nil); KIF::Coop::Mon.int(v, lo, hi, d); end

      # a number from the partner in range, else nil (nothing is clamped into a valid pick)
      def pick(v, lo, hi); (v.is_a?(Integer) && v.between?(lo, hi)) ? v : nil; end

      # a choice from the partner, checked like the player's own; false: the AI picks
      def apply(i, a)
        b = @battle.battlers[i]
        case a["a"]
        when "move"
          m = pick(a["m"], -1, 3) or return false
          return @battle.pbAutoChooseMove(i, false) if m < 0 || !@battle.pbCanShowFightMenu?(i)
          return false unless b.moves[m] && b.moves[m].id && @battle.pbRegisterMove(i, m, false)
          t = a["tg"]
          if t.is_a?(Integer) && t >= 0 && t < @battle.battlers.length && @battle.battlers[t] &&
             @battle.pbMoveCanTarget?(i, t, b.moves[m].pbTarget(b))
            @battle.pbRegisterTarget(i, t)
          end
          return true
        when "switch"
          p = pick(a["p"], 0, 5)
          return false unless p && slot?(start + p)
          return @battle.pbRegisterSwitch(i, start + p)
        when "item" then return apply_item(i, b, a)
        when "run"
          return false unless @battle.wildBattle?
          r = @battle.pbRun(i)
          @battle.choices[i][0] = :Run if r < 0   # didn't get away: the turn is used, as the player's is
          return r != 0
        end
        return false
      end

      def apply_item(i, b, a)
        it = KIF::Coop::Mon.sym(a["i"], GameData::Item) or return false
        use = GameData::Item.get(it).battle_use.to_i
        mv = a.key?("mv") ? pick(a["mv"], -1, 3) : -1
        return false unless mv
        case use
        when 1, 2, 3, 6, 7, 8
          p = pick(a["p"], 0, 5)
          return false unless p && slot?(start + p)
          abs = start + p
          bt = @battle.pbFindBattler(abs, i)
          if [3, 8].include?(use)
            return false unless bt && ItemHandlers.hasBattleUseOnBattler(it)
            pk = bt.pokemon
          else
            return false unless ItemHandlers.hasBattleUseOnPokemon(it)
            pk = @battle.pbParty(i)[abs]
          end
          return false unless pk && @battle.pbCanUseItemOnPokemon?(it, pk, bt, @battle.scene, false)
          return false unless ItemHandlers.triggerCanUseInBattle(it, pk, bt, mv, true, @battle, @battle.scene, false)
          return @battle.pbRegisterItem(i, it, abs, mv)
        when 4, 9
          # its own game already checked the ball against its own rules (Nuzlocke, room in the PC)
          t = a["tb"]
          return false unless @battle.wildBattle? && t.is_a?(Integer) && @battle.battlers[t] && @battle.opposes?(t) && !@battle.battlers[t].fainted?
          return @battle.pbRegisterItem(i, it, t, -1)
        when 5, 10
          return false unless ItemHandlers.triggerCanUseInBattle(it, b.pokemon, b, -1, true, @battle, @battle.scene, false)
          return @battle.pbRegisterItem(i, it, i, -1)
        end
        return false
      end

      # the partner's replacement (party index), -1 (cancelled) or nil (the AI picks)
      def choose_switch(idx, lax, cancel)
        return nil unless connected? && !@auto
        flush
        @swn += 1
        n = @swn
        post("co_sw", "d" => { "b" => idx, "n" => n, "c" => cancel ? 1 : 0, "ord" => order, "pt" => party_state })
        ans = nil
        got = wait(KIF::Coop.sw_wait, wait_text) do
          while (r = KIF::Coop.take_host(@id, ["co_swr", "co_act"]))
            if r[0] == "co_act"
              @auto = true if r[1]["d"]["b"] == -1
              next
            end
            ans = r[1]["d"] if r[1]["d"]["n"] == n
          end
          ans || @auto
        end
        return nil unless got && ans
        p = ans["p"]
        return -1 if cancel && p == -1
        return nil unless p.is_a?(Integer) && p >= 0 && slot?(start + p)
        abs = start + p
        ok = lax ? @battle.pbCanSwitchLax?(idx, abs) : @battle.pbCanSwitch?(idx, abs)
        return ok ? abs : nil
      end

      #-------------------------------------------------------------------------
      # Exp, catches, items
      #-------------------------------------------------------------------------
      # pbGainExp is about to pay out: note each defeated foe (the partner's
      # game pays its own Pokémon: participants, Exp Share, Exp All)
      def note_kills
        return unless @battle.internalBattle && @battle.expGain
        @battle.battlers.each do |b|
          next unless b && b.opposes? && b.pokemon && !b.participants.empty? && (b.fainted? || b.captured)
          # all of them, as host party indices: the partner's Exp Share needs a fought foe too
          @kills << { "s" => b.pokemon.species.to_s, "l" => b.level, "p" => b.participants.first(12) } if @kills.length < 60
        end
      end

      def caught_by_guest(list)
        @caught.concat(list)
        KIF::Coop.log("#{@name} caught #{list.map(&:name).join(', ')}") unless list.empty?
      end

      # consumed items the partner used (+1) or got back (-1)
      def item_used(item, n)
        use = GameData::Item.get(item).battle_use.to_i rescue 0
        @items[item] += n if use.between?(1, 5)
      end

      def finish(decision, why = nil)
        return if @done
        flush if @battle
        @done = true
        d = { "dc" => decision.to_i }
        if @battle && !why
          d["cl"] = @battle.canLose ? 1 : 0
          d["pt"] = guest_party.map { |p| p ? [p.hp, p.status.to_s, p.statusCount.to_i, p.moves.map { |m| m.pp.to_i }] : nil }
          d["k"] = @kills
          d["c"] = @caught.first(6).map { |p| KIF::Coop::Mon.dump(p, true) }
          d["it"] = @items.select { |_k, v| v > 0 }.map { |k, v| [k.to_s, v] }
        end
        d["x"] = why if why
        post("co_end", "d" => d) if connected?
        KIF::Coop.log("battle #{@id} over (#{why || decision})")
      end
    end

    #---------------------------------------------------------------------------
    # The host's battle scene (this battle's object only): each thing it shows
    # goes into the log. Only the outermost call counts (sending out plays the
    # shiny animation itself), and nothing while the battle is quiet (this
    # player's Exp, money, catches, questions only this player answers).
    #---------------------------------------------------------------------------
    module Capture
      def kif_rec(always = false)
        c = @kif_coop
        return unless c && @kif_cap_depth.to_i == 0 && (always || !c.quiet?)
        ev = yield
        c.push(ev[0], ev[1]) if ev
      rescue StandardError => e
        KIF::Coop.log("log entry skipped (#{e.class}: #{e.message})")
      end

      def kif_in
        @kif_cap_depth = @kif_cap_depth.to_i + 1
        return yield
      ensure
        @kif_cap_depth -= 1
      end

      def kif_i(b); b.respond_to?(:index) ? b.index : (b.is_a?(Integer) ? b : -1); end
      def kif_t(m); KIF::Coop::Mon.text(m.to_s); end

      def pbStartBattle(*args, &blk)
        (@kif_coop.begin_battle rescue KIF::Coop.log("begin not sent (#{$!.class}: #{$!.message})")) if @kif_coop
        kif_in { super }
      end

      def pbDisplayMessage(*args, &blk)
        kif_rec { ["m", [kif_t(args[0]), args[1] ? 1 : 0]] }
        kif_in { super }
      end

      def pbDisplayPausedMessage(*args, &blk)
        kif_rec { ["mp", [kif_t(args[0])]] }
        kif_in { super }
      end

      def pbSendOutBattlers(*args, &blk)
        kif_rec do
          list = (args[0] || []).map do |i, pk|
            b = @battle.battlers[i]
            shown = (b.effects[PBEffects::Illusion] rescue nil) || pk
            [i, b.pokemonIndex, KIF::Coop::Mon.dump(shown)]
          end
          ["so", [list, args[1] ? 1 : 0]]
        end
        kif_in { super }
      end

      def pbRecall(*args, &blk)
        kif_rec { ["rc", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbHPChanged(*args, &blk)
        kif_rec { ["hp", [kif_i(args[0]), args[1].to_i, args[2] ? 1 : 0]] }
        kif_in { super }
      end

      def pbDamageAnimation(*args, &blk)
        kif_rec { ["da", [kif_i(args[0]), args[1].to_i]] }
        kif_in { super }
      end

      def pbHitAndHPLossAnimation(*args, &blk)
        kif_rec { ["hl", [(args[0] || []).map { |t| [kif_i(t[0]), t[1].to_i, t[2].to_i] }]] }
        kif_in { super }
      end

      def pbFaintBattler(*args, &blk)
        kif_rec { ["fa", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbAnimation(*args, &blk)
        kif_rec do
          t = args[2]
          t = [t] unless t.is_a?(Array)
          ["an", [args[0].to_s, kif_i(args[1]), t.compact.map { |x| kif_i(x) }, args[3].to_i]]
        end
        kif_in { super }
      end

      def pbCommonAnimation(*args, &blk)
        kif_rec do
          t = args[2].is_a?(Array) ? args[2][0] : args[2]
          ["ca", [args[0].to_s, args[1] ? kif_i(args[1]) : -1, t ? kif_i(t) : -1]]
        end
        kif_in { super }
      end

      def pbShowAbilitySplash(*args, &blk)
        kif_rec do
          name = args[1..-1].find { |a| a.is_a?(String) } || (args[0].abilityName rescue "")
          ["ab", [kif_i(args[0]), args[1] == true ? 1 : 0, name.to_s[0, 40]]]
        end
        kif_in { super }
      end

      def pbHideAbilitySplash(*args, &blk)
        kif_rec { ["abh", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbReplaceAbilitySplash(*args, &blk)
        kif_rec { ["ab", [kif_i(args[0]), 0, (args[0].abilityName rescue "").to_s[0, 40]]] }
        kif_in { super }
      end

      def pbChangePokemon(*args, &blk)
        kif_rec { ["ch", [kif_i(args[0]), KIF::Coop::Mon.dump(args[1])]] if args[1].is_a?(Pokemon) }
        kif_in { super }
      end

      def pbRefresh(*args, &blk)
        kif_rec { ["rf", []] }
        kif_in { super }
      end

      def pbRefreshOne(*args, &blk)
        kif_rec { ["r1", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbShowOpponent(*args, &blk)
        kif_rec { ["op", [args[0].to_i]] }
        kif_in { super }
      end

      def pbShowPartyLineup(*args, &blk)
        kif_rec { ["pl", [args[0].to_i, args[1] ? 1 : 0]] }
        kif_in { super }
      end

      def pbThrow(*args, &blk)
        kif_rec { ["th", [args[0].to_s, args[1].to_i, args[2] ? 1 : 0, kif_i(args[3]), args[4] ? 1 : 0]] }
        kif_in { super }
      end

      def pbThrowSuccess(*args, &blk)
        kif_rec { ["ts", []] }
        kif_in { super }
      end

      def pbHideCaptureBall(*args, &blk)
        kif_rec { ["hc", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbThrowAndDeflect(*args, &blk)
        kif_rec { ["td", [args[0].to_s, kif_i(args[1])]] }
        kif_in { super }
      end

      def pbWildBattleSuccess(*args, &blk)
        kif_rec(true) { ["ws", []] }
        kif_in { super }
      end

      def pbTrainerBattleSuccess(*args, &blk)
        kif_rec(true) { ["tw", []] }
        kif_in { super }
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Hooks (each is the plain PIF path unless this battle is a co-op one)
#-------------------------------------------------------------------------------
alias kif_coop_pbWildBattleCore pbWildBattleCore unless defined?(kif_coop_pbWildBattleCore)
alias kif_coop_pbTrainerBattleCore pbTrainerBattleCore unless defined?(kif_coop_pbTrainerBattleCore)
alias kif_coop_pbPrepareBattle pbPrepareBattle unless defined?(kif_coop_pbPrepareBattle)
alias kif_coop_pbAfterBattle pbAfterBattle unless defined?(kif_coop_pbAfterBattle)

def pbWildBattleCore(*args)
  return kif_coop_pbWildBattleCore(*args) unless KIF::Coop.may_host?
  KIF::Coop.host_battle(:wild, KIF::Coop.count_wild(args)) { kif_coop_pbWildBattleCore(*args) }
end

def pbTrainerBattleCore(*args)
  return kif_coop_pbTrainerBattleCore(*args) unless KIF::Coop.may_host?
  KIF::Coop.host_battle(:trainer, nil) { kif_coop_pbTrainerBattleCore(*args) }
end

def pbPrepareBattle(battle)
  ret = kif_coop_pbPrepareBattle(battle)
  begin
    KIF::Coop.prepare(battle) if KIF::Coop.pending_host
  rescue => e
    KIF::Coop.log("couldn't set up the co-op battle (#{e.class}: #{e.message})")
  end
  return ret
end

# PIF heals both teams after a partner battle; a co-op battle doesn't
def pbAfterBattle(decision, canLose)
  return kif_coop_pbAfterBattle(decision, canLose) unless KIF::Coop.hosting?
  old = $PokemonGlobal.partner
  $PokemonGlobal.partner = nil
  begin
    return kif_coop_pbAfterBattle(decision, canLose)
  ensure
    $PokemonGlobal.partner = old
  end
end

class PokeBattle_Battle
  attr_reader :kif_coop

  alias kif_coop_pbCommandPhaseLoop pbCommandPhaseLoop unless method_defined?(:kif_coop_pbCommandPhaseLoop)
  alias kif_coop_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:kif_coop_pbSwitchInBetween)
  alias kif_coop_pbGainExp pbGainExp unless method_defined?(:kif_coop_pbGainExp)
  alias kif_coop_pbUsePokeBallInBattle pbUsePokeBallInBattle unless method_defined?(:kif_coop_pbUsePokeBallInBattle)
  alias kif_coop_pbRegisterItem pbRegisterItem unless method_defined?(:kif_coop_pbRegisterItem)
  alias kif_coop_pbReturnUnusedItemToBag pbReturnUnusedItemToBag unless method_defined?(:kif_coop_pbReturnUnusedItemToBag)
  alias kif_coop_pbEndOfBattle pbEndOfBattle unless method_defined?(:kif_coop_pbEndOfBattle)

  # player first (the partner is asked at the same time), then the AI
  def pbCommandPhaseLoop(isPlayer)
    c = @kif_coop
    if c
      begin
        isPlayer ? c.ask_commands : c.take_commands
      rescue => e
        KIF::Coop.log("turn step failed (#{e.class}: #{e.message})")
      end
    end
    return kif_coop_pbCommandPhaseLoop(isPlayer)
  end

  def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
    c = @kif_coop
    if c && c.guest?(idxBattler)
      r = (c.choose_switch(idxBattler, checkLaxOnly, canCancel) rescue nil)
      return r if r
    end
    return kif_coop_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
  end

  def pbGainExp(*args)
    c = @kif_coop
    return kif_coop_pbGainExp(*args) unless c
    (c.note_kills rescue nil)
    return c.quietly { kif_coop_pbGainExp(*args) }
  end

  # the partner's ball: a catch is the partner's
  def pbUsePokeBallInBattle(item, idxBattler, userBattler)
    c = @kif_coop
    return kif_coop_pbUsePokeBallInBattle(item, idxBattler, userBattler) unless c && userBattler && c.guest?(userBattler.index)
    n = @caughtPokemon.length
    ret = kif_coop_pbUsePokeBallInBattle(item, idxBattler, userBattler)
    c.caught_by_guest(@caughtPokemon.slice!(n..-1) || [])
    return ret
  end

  def pbRegisterItem(idxBattler, item, idxTarget = nil, idxMove = nil)
    c = @kif_coop
    c.item_used(item, 1) if c && item && c.guest?(idxBattler)
    return kif_coop_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
  end

  def pbReturnUnusedItemToBag(item, idxBattler)
    c = @kif_coop
    c.item_used(item, -1) if c && item && c.guest?(idxBattler)
    return kif_coop_pbReturnUnusedItemToBag(item, idxBattler)
  end

  def pbEndOfBattle(*args)
    ret = kif_coop_pbEndOfBattle(*args)
    (@kif_coop.finish(@decision) rescue KIF::Coop.log("result not sent (#{$!.class}: #{$!.message})")) if @kif_coop
    return ret
  end

  # this player's own money, catches and moves: not in the partner's log
  [:pbGainMoney, :pbLoseMoney, :pbGainCosmeticsMoney, :pbRecordAndStoreCaughtPokemon, :pbLearnMove].each do |m|
    next unless method_defined?(m)
    orig = :"kif_coop_q_#{m}"
    alias_method orig, m unless method_defined?(orig)
    define_method(m) do |*args, &blk|
      c = @kif_coop
      return send(orig, *args, &blk) unless c
      return c.quietly { send(orig, *args, &blk) }
    end
  end
end
