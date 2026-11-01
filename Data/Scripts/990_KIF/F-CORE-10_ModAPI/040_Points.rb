#===============================================================================
# F-CORE-10 Mod API - where the events fire (the ONE file that wraps game methods)
#
# Every event of 020_Events.rb is tied here to a game method (or an Events
# callback). The wrapper is installed THE FIRST TIME someone subscribes
# (lazy arming), through the hook engine of 030_Hook.rb, so an event nobody
# listens to costs nothing. After the last subscriber leaves, the wrapper
# stays and costs one method call and one array test.
#
# A row says: Points.define(event, "Class#method", at: :before | :after,
#   cancel:, skip:, pre:, fields:, apply:, descend:, also:)
#   fields  builds the ctx fields from the Call (receiver, args, result);
#           it may return nil to skip this firing
#   apply   reads the changeable fields back (validated with ctx.valid) and
#           writes them into the call (args before, result after)
#   cancel  true: ctx.cancel! skips the method and returns `skip`
#   descend true: subclasses that define the method themselves are wrapped
#           too (found live, so a missed override can not happen)
#   also    more targets ("PokeBattle_SafariZone#pbStartBattle")
# A subclass override that calls super fires the event once: the inner call
# sees the "in flight" mark of the outer one and passes through.
#
# Always-on core points (installed by install_core!, whether or not anyone
# subscribed; they are protections, not events):
#  1. Event#trigger / trigger2: a callback that comes from a MOD raises into
#     the log (with the mod's name), the next callback and the game go on.
#     KIF's and the game's own callbacks still propagate as before.
#  2. KIF::Mods.load_file: timing per mod and the method-collision check.
#  3. KIF::DataLoad.after_load_all: a mod's step names its mod when it fails.
#  4. PluginManager.runPlugins: the :mods_loading / :mod_loaded / :mods_loaded
#     sequence, the repair of wrappers (heal!), the waiting when_loaded blocks.
#===============================================================================
module KIF
  module API
    module Points
      Row = Struct.new(:event, :target, :at, :cancel, :skip, :pre, :fields, :apply, :descend, :also) unless const_defined?(:Row)
      BUS_EVENTS = [:mods_loading, :mod_loaded, :mods_loaded].freeze unless const_defined?(:BUS_EVENTS)
      PRIORITY = -500 unless const_defined?(:PRIORITY)   # outside mods' own hooks

      @rows     = {}      # event => [Row]
      @bridges  = {}      # event => [source lambda, builder]
      @armed    ||= {}    # event => [Subscription] (the wrapper entries)
      @bridged  ||= {}    # event => the callback added to an Events object
      @inflight ||= {}    # event => { key => true }
      @mod_stats ||= {}   # mod key => { :ms, :files }
      @last_scene = nil
      @data_loads ||= 0
      @last_tick ||= nil

      class << self
        attr_reader :rows, :bridges, :armed, :mod_stats
      end

      def self.define(event, target, at: :after, cancel: false, skip: nil, pre: nil, fields: nil, apply: nil, descend: false, also: [])
        (@rows[event] ||= []) << Row.new(event, target, at, cancel, skip, pre, fields, apply, descend, also)
      end

      def self.bridge(event, source, builder)
        @bridges[event] = [source, builder]
      end

      # every target text of the table (the collision snapshot watches them)
      def self.targets
        t = []
        @rows.each_value { |l| l.each { |r| t << r.target; t.concat(r.also) } }
        return t.uniq
      end

      #-------------------------------------------------------------------------
      # Small readers: the field builders must never break a game method
      #-------------------------------------------------------------------------
      def self.arg(c, i, default = nil)
        a = c.args
        return a.length > i ? a[i] : default
      end

      def self.get(obj, *names)
        names.each do |n|
          return obj.send(n) if obj.respond_to?(n)
          iv = :"@#{n.to_s.sub(/\?\z/, '')}"
          return obj.instance_variable_get(iv) if obj.instance_variable_defined?(iv)
        end
        return nil
      end

      def self.double?(b)
        return b.pbSideSize(0) > 1 if b.respond_to?(:pbSideSize)
        return get(b, :doublebattle) ? true : false
      rescue StandardError
        return false
      end

      def self.scope
        return :battle if $game_temp && $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
        s = $scene
        return :other if s.nil?
        return :map if defined?(::Scene_Map) && s.is_a?(::Scene_Map)
        n = s.class.name.to_s
        return :title if n =~ /Title|Intro|Load/
        return :menu if n =~ /Menu|Pause|Bag|Party|Pokedex|Storage|Option/
        return :other
      end

      #-------------------------------------------------------------------------
      # Arming
      #-------------------------------------------------------------------------
      # Called by the bus when an event gets its first subscriber.
      def self.arm(ev)
        return if @armed[ev]
        if @bridges[ev]
          arm_bridge(ev)
          return
        end
        rows = @rows[ev]
        return unless rows
        @armed[ev] = []
        rows.each { |row| arm_row(row) }
      end

      def self.arm_row(row)
        list = [row.target] + row.also
        list.each do |t|
          r = Hook.resolve(t)
          next unless r && Hook.method_exists?(r[0], r[1], r[2])
          wrap(row, r[0], r[1], r[2])
          next unless row.descend && !r[2]
          descendants_defining(r[0], r[1]).each { |k| wrap(row, k, r[1], false) }
        end
      end

      def self.wrap(row, klass, name, single)
        blk = proc { |call| Points.run_row(row, call) }
        sub = Hook.attach(:around, klass, name, single, "pt:#{row.event}", PRIORITY, nil, blk, true)
        (@armed[row.event] ||= []) << sub if sub
      end

      # subclasses (any depth) that define `name` themselves
      def self.descendants_defining(klass, name)
        out = []
        stack = [klass]
        until stack.empty?
          k = stack.pop
          k.subclasses.each do |s|
            out << s if Hook.own_method?(s, name)
            stack << s
          end
        end
        return out
      rescue StandardError
        return out
      end

      # Classes loaded after arming (a mod's subclass): wrap the new overrides too.
      def self.rescan!
        @armed.keys.each do |ev|
          (@rows[ev] || []).each do |row|
            next unless row.descend
            r = Hook.resolve(row.target)
            next unless r
            have = @armed[ev].map { |s| s.target.klass }
            descendants_defining(r[0], r[1]).each { |k| wrap(row, k, r[1], false) unless have.include?(k) }
          end
        end
      end

      def self.disarm_if_idle(ev)
        subs = @armed[ev]
        if subs
          subs.each { |s| Hook.detach(s) }
          @armed.delete(ev)
        end
        disarm_bridge(ev)
      end

      def self.arm_bridge(ev)
        return if @bridged[ev]
        src, builder = @bridges[ev]
        evobj = (src.call rescue nil)
        return unless evobj
        cb = builder.call(ev)
        evobj + cb
        @bridged[ev] = cb
        @armed[ev] = []
      end

      def self.disarm_bridge(ev)
        cb = @bridged.delete(ev)
        return unless cb
        src, = @bridges[ev]
        evobj = (src.call rescue nil)
        evobj - cb if evobj
        @armed.delete(ev)
      end

      #-------------------------------------------------------------------------
      # What the wrapper does for one call
      #-------------------------------------------------------------------------
      def self.run_row(row, call)
        ev = row.event
        return call.proceed unless API.listening?(ev)
        inf = (@inflight[ev] ||= {})
        key = call.receiver.object_id * 1_000_003 + (call.args.empty? ? 0 : call.args[0].object_id)
        return call.proceed if inf[key]
        inf[key] = true
        begin
          safely(row, :pre) { row.pre.call(call) } if row.pre
          if row.at == :before
            ctx = emit_row(row, call)
            if ctx
              safely(row, :apply) { row.apply.call(ctx, call) } if row.apply
              if row.cancel && ctx.cancelled?
                return row.skip.respond_to?(:call) ? row.skip.call(call) : row.skip
              end
            end
            return call.proceed
          end
          call.proceed
          ctx = emit_row(row, call)
          safely(row, :apply) { row.apply.call(ctx, call) } if ctx && row.apply
          return call.result
        ensure
          inf.delete(key)
        end
      end

      def self.emit_row(row, call)
        f = row.fields ? row.fields.call(call) : {}
        return nil if f.nil?
        return API.fire(row.event, f)
      rescue StandardError => e
        API.say("pointfields:#{row.event}:#{e.class}", "Mod API: event :#{row.event} could not be built (#{e.class}: #{e.message[0, 100]}); skipped")
        return nil
      end

      def self.safely(row, what)
        yield
      rescue StandardError => e
        API.say("pointapply:#{row.event}:#{what}:#{e.class}", "Mod API: event :#{row.event} #{what} failed (#{e.class}: #{e.message[0, 100]})")
      end

      #-------------------------------------------------------------------------
      # THE TABLE. Fields are documented in 020_Events.rb.
      #-------------------------------------------------------------------------
      A = lambda { |c, i, d = nil| c.args.length > i ? c.args[i] : d } unless const_defined?(:A)

      # --- loading and the game (singleton methods) -------------------------
      define :data_loaded, "GameData.load_all", at: :after,
             fields: ->(c) { { :reload => Points.data_loads > 1 } }
      define :game_new, "Game.start_new", at: :after,
             fields: ->(c) { { :new_game_plus => c.args.any? { |x| x } } }
      define :game_loading, "Game.load", at: :before,
             fields: ->(c) { d = A.(c, 0); { :keys => (d.is_a?(Hash) ? d.keys : []) } }
      define :game_loaded, "Game.load", at: :after, fields: ->(c) { {} }
      define :game_saving, "Game.save", at: :before,
             fields: ->(c) { { :path => (A.(c, 0) || (defined?(SaveData::FILE_PATH) ? SaveData::FILE_PATH : "")), :safe => (c.kwargs[:safe] ? true : false) } }
      define :game_saved, "Game.save", at: :after,
             fields: ->(c) { { :path => (A.(c, 0) || (defined?(SaveData::FILE_PATH) ? SaveData::FILE_PATH : "")), :ok => (c.result ? true : false) } }
      define :frame, "Graphics.update", at: :after,
             fields: ->(c) { { :scope => Points.scope, :frame_count => Graphics.frame_count } }
      define :tick, "Graphics.update", at: :after,
             fields: ->(c) { fc = Graphics.frame_count; next nil if fc == Points.last_tick; Points.last_tick = fc; { :scope => Points.scope, :frame_count => fc } }
      define :scene_open, "Graphics.update", at: :after,
             fields: ->(c) { k = $scene.class; next nil if k.equal?(Points.last_scene); Points.last_scene = k; { :scene => $scene, :name => k.name.to_s } }

      define :pause_menu_build, "KIF::PauseMenu.active_entries", at: :after,
             fields: ->(c) { { :entries => Array(c.result).map { |e| e.dup } } },
             apply: ->(ctx, c) { c.result = ctx.valid(:entries) }

      # --- map and events ----------------------------------------------------
      define :interact_start, "Game_Event#start", at: :before, cancel: true, skip: nil,
             fields: ->(c) { { :event => c.receiver, :map_id => Points.get(c.receiver, :map_id) } }
      define :interact_check, "Game_Player#check_event_trigger_there", at: :before, cancel: true, skip: false,
             fields: ->(c) { { :triggers => A.(c, 0) } }
      define :encounter_roll, "PokemonEncounters#encounter_triggered?", at: :after,
             fields: ->(c) { { :encounters => c.receiver, :enc_type => A.(c, 0), :repel_active => A.(c, 1, false),
                               :by_step => A.(c, 2, true), :map_id => ($game_map ? $game_map.map_id : nil), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :encounter_choose, "PokemonEncounters#choose_wild_pokemon", at: :after,
             fields: ->(c) { { :encounters => c.receiver, :enc_type => A.(c, 0), :chance_rolls => A.(c, 1, 1),
                               :map_id => ($game_map ? $game_map.map_id : nil), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :item_stored, "PokemonBag#pbStoreItem", at: :after,
             fields: ->(c) { { :bag => c.receiver, :item => A.(c, 0), :qty => A.(c, 1, 1) } }
      define :shop_stock, "Object#get_mart_exclusive_items", at: :after,
             fields: ->(c) { { :city => A.(c, 0), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :item_found, "Object#pbItemBall", at: :before, cancel: true, skip: false,
             fields: ->(c) { { :item_name => A.(c, 2, ""), :item => A.(c, 0), :quantity => A.(c, 1, 1) } },
             apply: ->(ctx, c) { a = c.args.dup; a[0] = ctx.valid(:item); a[1] = ctx.valid(:quantity); c.args = a }

      # --- battle ------------------------------------------------------------
      define :battle_start, "PokeBattle_Battle#pbStartBattle", at: :before, descend: true, also: ["PokeBattle_SafariZone#pbStartBattle"],
             fields: ->(c) { b = c.receiver; { :battle => b, :wild => (b.respond_to?(:wildBattle?) ? b.wildBattle? : false),
                                               :trainer => Points.get(b, :opponent), :double => Points.double?(b) } }
      define :battle_loop, "PokeBattle_Battle#pbBattleLoop", at: :before, descend: true,
             fields: ->(c) { { :battle => c.receiver } }
      define :battle_end, "PokeBattle_Battle#pbEndOfBattle", at: :before, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :decision => Points.get(b, :decision), :can_lose => Points.get(b, :canLose) ? true : false } }
      define :battle_ended, "PokeBattle_Battle#pbEndOfBattle", at: :after, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :decision => Points.get(b, :decision) } }
      define :turn_start, "PokeBattle_Battle#pbCommandPhase", at: :before, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :turn => Points.get(b, :turnCount) } }
      define :attack_phase, "PokeBattle_Battle#pbAttackPhase", at: :before, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :turn => Points.get(b, :turnCount) } }
      define :round_end, "PokeBattle_Battle#pbEndOfRoundPhase", at: :before, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :turn => Points.get(b, :turnCount) } }
      define :round_ended, "PokeBattle_Battle#pbEndOfRoundPhase", at: :after, descend: true,
             fields: ->(c) { b = c.receiver; { :battle => b, :turn => Points.get(b, :turnCount) } }
      define :exp_gain, "PokeBattle_Battle#pbGainExp", at: :before, descend: true, fields: ->(c) { { :battle => c.receiver } }
      define :exp_gained, "PokeBattle_Battle#pbGainExp", at: :after, descend: true, fields: ->(c) { { :battle => c.receiver } }
      define :money_gain, "PokeBattle_Battle#pbGainMoney", at: :before, descend: true, fields: ->(c) { { :battle => c.receiver } }

      define :move_use, "PokeBattle_Battler#pbUseMove", at: :before, descend: true, cancel: true, skip: nil,
             fields: ->(c) { ch = A.(c, 0); { :battler => c.receiver, :battle => Points.get(c.receiver, :battle), :choice => ch,
                                               :move => (ch.is_a?(Array) ? ch[2] : nil), :special_usage => A.(c, 1, false) } }
      define :move_used, "PokeBattle_Battler#pbUseMove", at: :after, descend: true,
             fields: ->(c) { ch = A.(c, 0); { :battler => c.receiver, :battle => Points.get(c.receiver, :battle), :choice => ch,
                                               :move => (ch.is_a?(Array) ? ch[2] : nil), :special_usage => A.(c, 1, false) } }
      define :battler_faint, "PokeBattle_Battler#pbFaint", at: :before, descend: true,
             fields: ->(c) { { :battler => c.receiver, :battle => Points.get(c.receiver, :battle), :show_message => A.(c, 0, true) } }
      define :battler_fainted, "PokeBattle_Battler#pbFaint", at: :after, descend: true,
             fields: ->(c) { { :battler => c.receiver, :battle => Points.get(c.receiver, :battle) } }
      define :switch_in, "PokeBattle_Battler#pbEffectsOnSwitchIn", at: :before, descend: true,
             fields: ->(c) { { :battler => c.receiver, :battle => Points.get(c.receiver, :battle), :switch_in => A.(c, 0, false) } }
      define :battler_init, "PokeBattle_Battler#pbInitEffects", at: :after, descend: true,
             fields: ->(c) { { :battler => c.receiver, :battle => Points.get(c.receiver, :battle), :baton_pass => A.(c, 0, false) } }

      define :damage_multipliers, "PokeBattle_Move#pbCalcDamageMultipliers", at: :after, descend: true,
             pre: ->(c) { m = A.(c, 5); c.data[:saved] = m.dup if m.is_a?(Hash) },
             fields: ->(c) { next nil unless A.(c, 5).is_a?(Hash)
                             { :move => c.receiver, :user => A.(c, 0), :target => A.(c, 1), :num_targets => A.(c, 2), :type => A.(c, 3),
                               :base_damage => A.(c, 4), :multipliers => A.(c, 5) } },
             apply: ->(ctx, c) { Points.apply_multipliers(ctx, c) }
      define :type_effectiveness, "PokeBattle_Move#pbCalcTypeModSingle", at: :after, descend: true,
             fields: ->(c) { { :move => c.receiver, :move_type => A.(c, 0), :def_type => A.(c, 1), :user => A.(c, 2), :target => A.(c, 3), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :accuracy_check, "PokeBattle_Move#pbAccuracyCheck", at: :after, descend: true,
             fields: ->(c) { { :move => c.receiver, :user => A.(c, 0), :target => A.(c, 1), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :crit_check, "PokeBattle_Move#pbIsCritical?", at: :after, descend: true,
             fields: ->(c) { { :move => c.receiver, :user => A.(c, 0), :target => A.(c, 1), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :hit_count, "PokeBattle_Move#pbNumHits", at: :after, descend: true,
             fields: ->(c) { { :move => c.receiver, :user => A.(c, 0), :targets => A.(c, 1), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }

      define :ai_score_move, "PokeBattle_AI#pbGetMoveScoreFunctionCode", at: :after, descend: true,
             fields: ->(c) { { :ai => c.receiver, :move => A.(c, 1), :user => A.(c, 2), :target => A.(c, 3), :skill => A.(c, 4, 100), :score => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:score) }
      define :ai_rough_damage, "PokeBattle_AI#pbRoughDamage", at: :after, descend: true,
             fields: ->(c) { { :ai => c.receiver, :move => A.(c, 0), :user => A.(c, 1), :target => A.(c, 2), :skill => A.(c, 3), :result => c.result } },
             apply: ->(ctx, c) { c.result = ctx.valid(:result) }
      define :ai_choose, "PokeBattle_AI#pbDefaultChooseEnemyCommand", at: :before, descend: true, cancel: true, skip: nil,
             fields: ->(c) { { :ai => c.receiver, :battler_index => A.(c, 0), :battle => Points.get(c.receiver, :battle) } }

      # --- Pokemon, fusion ---------------------------------------------------
      define :fusion_before, "Object#pbFuse", at: :before, cancel: true, skip: false,
             fields: ->(c) { { :body => A.(c, 0), :head => A.(c, 1), :splicer => A.(c, 2) } }
      define :fusion_done, "Object#pbFuse", at: :after,
             fields: ->(c) { { :body => A.(c, 0), :head => A.(c, 1), :splicer => A.(c, 2), :result => c.result } }
      define :unfuse_done, "Object#pbUnfuse", at: :after,
             fields: ->(c) { { :pokemon => A.(c, 0), :party_position => A.(c, 2), :pc_position => A.(c, 3), :result => c.result } }
      define :pokemon_added, "Object#pbAddPokemon", at: :after,
             fields: ->(c) { { :pokemon => A.(c, 0), :result => c.result } }
      define :level_changed, "Object#pbChangeLevel", at: :after,
             pre: ->(c) { p = A.(c, 0); c.data[:old] = (p.respond_to?(:level) ? p.level : nil) },
             fields: ->(c) { p = A.(c, 0); { :pokemon => p, :old_level => c.data[:old], :new_level => (p.respond_to?(:level) ? p.level : nil) } }
      define :stats_calculated, "Pokemon#calc_stats", at: :after, fields: ->(c) { { :pokemon => c.receiver } }
      define :wild_battle_start, "Object#pbWildBattle", at: :before,
             fields: ->(c) { { :species => A.(c, 0), :level => A.(c, 1), :can_run => A.(c, 3, true), :can_lose => A.(c, 4, false) } },
             apply: ->(ctx, c) { a = c.args.dup; a[0] = ctx.valid(:species); a[1] = ctx.valid(:level); c.args = a }

      # --- screens -----------------------------------------------------------
      define :sprite_update, "Sprite_Character#update", at: :after, descend: true,
             fields: ->(c) { { :sprite => c.receiver, :character => Points.get(c.receiver, :character) } }
      define :sprite_dispose, "Sprite_Character#dispose", at: :before, descend: true,
             fields: ->(c) { { :sprite => c.receiver, :character => Points.get(c.receiver, :character) } }
      define :summary_page_drawn, "PokemonSummary_Scene#drawPage", at: :after,
             fields: ->(c) { s = c.receiver; sp = Points.get(s, :sprites); ov = sp.is_a?(Hash) ? sp["overlay"] : nil
                             { :scene => s, :pokemon => Points.get(s, :pokemon), :page => A.(c, 0), :overlay => (ov ? ov.bitmap : nil) } }
      define :party_panel_drawn, "PokemonPartyPanel#refresh", at: :after,
             fields: ->(c) { { :panel => c.receiver, :pokemon => Points.get(c.receiver, :pokemon), :bitmap => Points.get(c.receiver, :bitmap) } }
      define :databox_drawn, "PokemonDataBox#refresh", at: :after,
             fields: ->(c) { { :databox => c.receiver, :battler => Points.get(c.receiver, :battler), :bitmap => Points.get(c.receiver, :bitmap) } }
      define :storage_overlay_drawn, "PokemonStorageScene#pbUpdateOverlay", at: :after,
             fields: ->(c) { s = c.receiver; sp = Points.get(s, :sprites); ov = sp.is_a?(Hash) ? sp["overlay"] : nil
                             { :scene => s, :selection => A.(c, 0), :bitmap => (ov ? ov.bitmap : nil) } }

      # Events.onMapUpdate / onMapChange / onStepTaken: one KIF callback each, added when first needed
      bridge :map_update, -> { Events.onMapUpdate }, ->(ev) {
        proc { |*a| API.fire(:map_update, {}) if API.listening?(:map_update) }
      }
      bridge :map_changed, -> { Events.onMapChange }, ->(ev) {
        proc { |*a| API.fire(:map_changed, { :old_map_id => Array(a[1])[0], :new_map_id => ($game_map ? $game_map.map_id : nil) }) if API.listening?(:map_changed) }
      }
      bridge :step_taken, -> { Events.onStepTaken }, ->(ev) {
        proc { |*a| API.fire(:step_taken, { :event => $game_player, :map_id => ($game_map ? $game_map.map_id : nil),
                                              :x => ($game_player ? $game_player.x : nil), :y => ($game_player ? $game_player.y : nil) }) if API.listening?(:step_taken) }
      }

      #-------------------------------------------------------------------------
      # helpers the table uses
      #-------------------------------------------------------------------------
      class << self
        attr_accessor :last_tick, :last_scene
        attr_reader :data_loads
      end
      def self.data_loads_bump; @data_loads += 1; end

      # counts every GameData.load_all, listened to or not (a DataLoad step runs inside it)
      DATA_STEP = "ModAPI data load counter" unless const_defined?(:DATA_STEP)
      if defined?(KIF::DataLoad) && !(KIF::DataLoad.instance_variable_get(:@hooks) || []).any? { |n, _| n == DATA_STEP }
        KIF::DataLoad.after_load_all(DATA_STEP) { KIF::API::Points.data_loads_bump }
      end

      # damage_multipliers: keep what the game had unless the new value is a
      # finite number above 0 and at most 16
      def self.apply_multipliers(ctx, call)
        game = call.args[5]
        saved = call.data[:saved] || {}
        got = ctx.valid(:multipliers)
        game.merge!(got) if got.is_a?(Hash) && !got.equal?(game)
        game.each_key do |k|
          v = game[k]
          ok = v.is_a?(Numeric) && (!v.is_a?(Float) || v.finite?) && v > 0 && v <= 16
          next if ok
          if saved.key?(k) then game[k] = saved[k] else game.delete(k) end
          API.say("mult:#{ctx.mod}:#{k}", "Mod #{Attribution.display(ctx.mod)}: damage multiplier #{k} must be above 0 and at most 16; the game's value is kept")
        end
      end

      #-------------------------------------------------------------------------
      # Always-on core points
      #-------------------------------------------------------------------------
      # 1. a mod's Events callback that raises is logged, the others go on
      module EventIsolation
        def trigger(*arg)
          return super unless KIF::API::Points.event_base_ok?
          arglist = arg[1, arg.length]
          for callback in @callbacks
            begin
              if callback.arity > 2 && arg.length == callback.arity
                callback.call(*arg)
              else
                callback.call(arg[0], arglist)
              end
            rescue Exception => e
              raise unless KIF::API::Points.swallow_callback?(callback, e)
            end
          end
        end

        def trigger2(*arg)
          return super unless KIF::API::Points.event_base_ok?
          for callback in @callbacks
            begin
              callback.call(*arg)
            rescue Exception => e
              raise unless KIF::API::Points.swallow_callback?(callback, e)
            end
          end
        end
      end

      EVENT_FILE = "003_Game processing/005_Event_Handlers.rb" unless const_defined?(:EVENT_FILE)
      EVENT_CRC  = 3120683615 unless const_defined?(:EVENT_CRC)   # CRC32 of EVENT_FILE (line endings normalised): trigger and trigger2 below copy its loops

      @cb_owner = ObjectSpace::WeakMap.new unless @cb_owner

      def self.mod_of_callback(cb)
        v = (@cb_owner[cb] rescue nil)
        return (v == :none ? nil : v) if v
        loc = cb.respond_to?(:source_location) ? (cb.source_location rescue nil) : nil
        owner = loc ? KIF::ModContract.owner_of_path(loc[0]) : nil
        (@cb_owner[cb] = owner || :none) rescue nil
        return owner
      end

      # true: this callback came from a mod, the error is logged and swallowed
      def self.swallow_callback?(cb, e)
        return false if API.fatal?(e)
        key = mod_of_callback(cb)
        return false unless key
        API.say("cb:#{key}:#{cb.object_id}:#{e.class}:#{e.message[0, 60]}",
                "Mod \"#{Attribution.display(key)}\" Events callback raised #{e.class}: #{e.message[0, 160]} at #{(e.backtrace || [])[0].to_s.sub(/\A.*[\/\\]/, '')}")
        return true
      end

      # Our loops stand in for PIF's only while Event's own trigger is PIF's
      # (a mod that replaced it keeps its behaviour).
      def self.event_base_ok?
        return @event_ok unless @event_ok.nil?
        return check_event_base
      end

      def self.check_event_base
        um = Event.instance_method(:trigger)
        um = um.super_method while um && um.owner.equal?(EventIsolation)
        @event_ok = um && um.owner.equal?(Event) && um.source_location && um.source_location[0].to_s.end_with?("005_Event_Handlers.rb") ? true : false
      rescue StandardError
        @event_ok = false
      end

      def self.install_event_isolation
        KIF.guard_base(EVENT_FILE, EVENT_CRC, "Event#trigger / trigger2 (F-CORE-10 040_Points.rb)") if KIF.respond_to?(:guard_base)
        Event.prepend(EventIsolation) unless Event.ancestors.include?(EventIsolation)
        check_event_base
      end

      # 2. Mods.load_file: time per mod, collision check
      def self.core_load_file(call)
        id = call.args[1]
        @mod_stats[id] ||= { :ms => 0.0, :files => 0 }
        Collisions.before(id) if @mod_stats[id][:files] == 0
        t0 = API.clock
        r = call.proceed
        st = @mod_stats[id]
        st[:ms] += (API.clock - t0) * 1000.0
        st[:files] += 1
        Collisions.after(id)
        return r
      end

      # 3. after_load_all: a mod's step names its mod when it fails
      def self.core_after_load_all(call)
        blk = call.block
        return call.proceed unless blk
        locs = caller_locations(1, 40)
        key = Attribution.key_from_caller(locs)
        return call.proceed unless key
        step = call.args[0]
        call.block = proc do |*a|
          begin
            blk.call(*a)
          rescue Exception => e
            raise if API.fatal?(e)
            KIF.log("Mod \"#{Attribution.display(key)}\": data load step '#{step}' failed: #{e.class}: #{e.message[0, 160]}")
          end
        end
        return call.proceed
      end

      def self.install_core!
        install_event_isolation
        if defined?(KIF::Mods) && KIF::Mods.respond_to?(:load_file)
          Hook.attach(:around, KIF::Mods, :load_file, true, "core:load_file", -900, nil, proc { |call| Points.core_load_file(call) }, true)
        end
        if defined?(KIF::DataLoad) && KIF::DataLoad.respond_to?(:after_load_all)
          Hook.attach(:around, KIF::DataLoad, :after_load_all, true, "core:after_load_all", -900, nil, proc { |call| Points.core_after_load_all(call) }, true)
        end
        if defined?(KIF::Perf) && KIF::Perf.respond_to?(:bump_token)
          # nothing to wrap: documented only
        end
        return true
      end

      # 4. the sequence around PluginManager.runPlugins
      def self.before_mods!
        install_core!
        Attribution.refresh_roots!
        API.refresh_modes!
        @mod_stats.clear
        Attribution.invalidate
        if API.listening?(:mods_loading)
          API.fire(:mods_loading, { :mods => ((KIF::Mods.entries.map(&:id)) rescue []) })
        end
      end

      def self.after_mods!
        Attribution.invalidate
        Attribution.refresh_roots!
        infos = API.mods
        loaded = infos.select { |i| i.loaded }.map(&:key)
        failed = infos.select { |i| i.enabled && !i.loaded && i.kind != :mod_manager }.map(&:key)
        @mod_stats.each { |k, st| KIF.log("Mod #{Attribution.display(k)} took #{st[:ms].round} ms to load") if st[:ms] > 100 }
        infos.each do |i|
          st = @mod_stats[i.key] || { :ms => 0.0, :files => 0 }
          next unless API.listening?(:mod_loaded)
          API.fire(:mod_loaded, { :mod => i.key, :json_id => i.json_id, :name => i.name, :version => i.version,
                                   :ok => i.loaded, :error => i.error, :ms => st[:ms].round(1), :files => st[:files] })
        end
        total = @mod_stats.values.inject(0.0) { |s, h| s + h[:ms] }
        API.fire(:mods_loaded, { :loaded => loaded, :failed => failed, :ms => total.round(1) }) if API.listening?(:mods_loaded)
        Attribution.run_waiting
        Hook.heal!
        rescan!
        Collisions.forget_snapshots
        check_event_base
        return true
      end

      @plugins_wrapped ||= false
      def self.plugins_wrapped?; return @plugins_wrapped; end
      def self.plugins_wrapped!; @plugins_wrapped = true; end
    end
  end
end

module PluginManager
  class << self
    unless KIF::API::Points.plugins_wrapped?
      alias kifapi_runPlugins runPlugins
      KIF::API::Points.plugins_wrapped!
    end

    def runPlugins(*args)
      KIF::API::Points.before_mods!
      ret = kifapi_runPlugins(*args)
      KIF::API::Points.after_mods!
      return ret
    end
  end
end
