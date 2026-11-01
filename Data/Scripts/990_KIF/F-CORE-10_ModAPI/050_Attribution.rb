#===============================================================================
# F-CORE-10 Mod API - which mod is it, mod-to-mod calls, method collisions
#
# Every handler, hook, timer, data store and registry entry is tagged with the
# KEY of the mod that made it. The key is the mod's folder name (the file name
# for a loose .rb): KIF::Mods::Entry#id. It is found from the calling file's
# path (KIF::ModContract.caller_owner), not from "which mod is loading now",
# so work done later (a data-load step, a timer) still has an owner.
#
#   KIF::API.mods                  -> Array of Info (key, json_id, name, version, author,
#                                     kind, loaded, enabled, error, api_version, permissions)
#   KIF::API.mod("kif_er")         -> Info by key or by the mod.json id
#   KIF::API.mod_loaded?("kif_er"), KIF::API.mod_version("kif_er")
#   KIF::API.when_loaded("kif_er") { |info| ... }   run now if loaded, else when the
#                                  mods finished loading; never if it does not load.
#                                  Order does not matter: no load_after needed.
#   KIF::API.when_defined("Class#method") { ... }  the same for a method another mod defines
#   KIF::API.provide("my_mod.kit", object, version: 1) / api_of("my_mod.kit") / provided
#                                  announce an API your mod offers to other mods
#   KIF::API.collisions            -> list of "mod X replaced Class#m" (inspector)
#===============================================================================
module KIF
  module API
    Info = Struct.new(:key, :json_id, :name, :version, :author, :kind, :loaded, :enabled, :error,
                      :api_version, :permissions, :path) unless const_defined?(:Info)

    module Attribution
      @order   ||= {}     # mod key => load index (KIF first)
      @index   ||= nil
      @stamp   ||= nil
      @waiting ||= []     # [kind, id, key, blk]
      @roots_done ||= false

      # The mod a piece of running code belongs to, or nil (KIF, the base game).
      # Pass caller_locations(1, 40) taken in the method that is being guarded.
      def self.key_from_caller(locs)
        refresh_roots_once
        # the API's own frames (a registry helper that calls API.on) do not decide
        locs = locs.drop_while { |l| (l.path || "").include?("F-CORE-10_ModAPI") }
        k = KIF::ModContract.caller_owner(locs)
        return k if k
        cur = (defined?(KIF::Mods) && KIF::Mods.respond_to?(:current)) ? KIF::Mods.current : nil
        return cur
      rescue StandardError
        return nil
      end

      # the contract needs the mod roots; read once, again when the Mods list changes
      def self.refresh_roots_once
        # (a second script run empties the contract's roots: read them again)
        return if @roots_done && !KIF::ModContract.roots.empty?
        @roots_done = true
        KIF::ModContract.refresh_roots
      end

      def self.refresh_roots!
        @roots_done = false
        refresh_roots_once
      end

      # What the player sees for a key: the mod's name, "KIF" for KIF itself
      def self.display(key)
        return "KIF" if key.nil?
        n = (KIF::Mods.display_name(key) rescue nil)
        return (n || key).to_s
      end

      # Position in the load order (KIF = -1); handlers of a mod loaded earlier run first
      def self.load_index(key)
        return -1 if key.nil?
        return (@order[key] ||= 1000 + @order.length)
      end

      def self.json_id(key)
        i = API.mod(key)
        return i ? i.json_id : nil
      end

      def self.invalidate; @index = nil; end

      #-------------------------------------------------------------------------
      # The list of installed mods
      #-------------------------------------------------------------------------
      def self.stamp
        return [(KIF::Mods.entries.length rescue 0), (KIF::Mods.status.length rescue 0),
                ((KIF::Mods.status.values.count { |s| s[:loaded] }) rescue 0), (KIF::Mods.disabled.length rescue 0)]
      end

      def self.index
        st = stamp
        return @index if @index && @stamp == st
        @stamp = st
        seen = {}
        list = []
        (KIF::Mods.entries rescue []).each do |e|
          json = (KIF::ModRules.json_for(e) rescue nil) || {}
          jid = json["id"] ? json["id"].to_s : nil
          jid = nil if jid && seen[jid.downcase]   # two mods with one id: the first keeps it
          seen[jid.downcase] = true if jid
          perms = json["permissions"].is_a?(Array) ? json["permissions"].map(&:to_s) : nil
          list << Info.new(e.id, jid, e.name.to_s, e.version, e.author, e.kind, e.loaded ? true : false,
                           (e.enabled? rescue true), (e.error ? e.error.to_s[0, 160] : nil),
                           json["api_version"], perms, e.path)
        end
        return @index = list
      end

      #-------------------------------------------------------------------------
      # Waiting for other mods
      #-------------------------------------------------------------------------
      def self.wait(kind, id, key, blk)
        @waiting << [kind, id, key, blk]
      end

      # Called after the mods loaded (and by tests): runs what can run now.
      def self.run_waiting
        todo = @waiting.dup
        @waiting.clear
        todo.each do |kind, id, key, blk|
          if kind == :mod
            info = API.mod(id)
            next unless info && info.loaded
            run_waiter(blk, key, info)
          else
            next unless API::Hook.exists?(id)
            run_waiter(blk, key, id)
          end
        end
      end

      def self.run_waiter(blk, key, arg)
        blk.call(arg)
      rescue Exception => e
        raise if API.fatal?(e)
        API.say("waiter:#{key}:#{e.class}:#{e.message[0, 60]}", "Mod \"#{display(key)}\": a when_loaded / when_defined block raised #{e.class}: #{e.message[0, 160]}")
      end

      def self.unload(key)
        @waiting.reject! { |_k, _i, kk, _b| kk == key }
      end
    end

    #---------------------------------------------------------------------------
    # Mods and their versions
    #---------------------------------------------------------------------------
    def self.mods; return Attribution.index.dup; end

    def self.mod(id)
      return nil if id.nil?
      s = id.to_s.downcase
      return Attribution.index.find { |i| i.key.to_s.downcase == s } || Attribution.index.find { |i| i.json_id && i.json_id.downcase == s }
    end

    # true when the mod loaded this session
    def self.mod_loaded?(id)
      i = mod(id)
      return i ? i.loaded : false
    end

    def self.mod_version(id)
      i = mod(id)
      return i ? i.version : nil
    end

    # Runs the block once the mod has loaded: at once if it already did, else
    # after all mods loaded. Never runs if that mod does not load.
    def self.when_loaded(id, &blk)
      raise ArgumentError, "when_loaded needs a block" unless blk
      key = Attribution.key_from_caller(caller_locations(1, 40))
      info = mod(id)
      if info && info.loaded
        Attribution.run_waiter(blk, key, info)
      else
        Attribution.wait(:mod, id, key, blk)
      end
      return true
    end

    # Runs the block once "Class#method" (or "Class.method") exists.
    def self.when_defined(target, &blk)
      raise ArgumentError, "when_defined needs a block" unless blk
      key = Attribution.key_from_caller(caller_locations(1, 40))
      if Hook.exists?(target)
        Attribution.run_waiter(blk, key, target)
      else
        Attribution.wait(:method, target, key, blk)
      end
      return true
    end

    #---------------------------------------------------------------------------
    # APIs mods offer each other
    #---------------------------------------------------------------------------
    @provided ||= {}

    # Announce an API: KIF::API.provide("my_mod.kit", MyMod::Kit, version: 2).
    # The first provider of a name keeps it.
    def self.provide(name, object, version: 1)
      key = Attribution.key_from_caller(caller_locations(1, 40))
      n = name.to_s
      old = @provided[n]
      if old && old[:mod] != key
        say("provide:#{n}", "Mod \"#{Attribution.display(key)}\" tried to provide \"#{n}\", already provided by \"#{Attribution.display(old[:mod])}\"")
        return false
      end
      @provided[n] = { :mod => key, :version => version, :object => object }
      return true
    end

    def self.api_of(name); h = @provided[name.to_s]; return h ? h[:object] : nil; end

    # name => { :mod, :version } (the objects stay with api_of)
    def self.provided
      out = {}
      @provided.each { |n, h| out[n] = { :mod => h[:mod], :version => h[:version] } }
      return out
    end

    on_unload(:attribution) do |key|
      @provided.delete_if { |_n, h| h[:mod] == key }
      Attribution.unload(key)
    end

    #---------------------------------------------------------------------------
    # Collisions: a mod REPLACED a method other code wraps. Taken as a snapshot
    # of the watched methods' [source file, original name, owner is the class]
    # before a mod's first file loads, and compared after its last.
    #---------------------------------------------------------------------------
    module Collisions
      @list ||= []
      @snap ||= {}
      # the methods mods hook most often on this PC (mod survey, 2026-11-01)
      SURVEY = %w[
        Sprite_Character#update GameData::Item.icon_filename PokemonDataBox#refresh Scene_Map#update
        PokemonPauseMenu_Scene#pbShowCommands Game_Event#start PokeBattle_Battle#pbStartBattle PokeBattle_Scene#pbFightMenu
        PokemonSummary_Scene#drawPage PokemonPartyPanel#refresh PokeBattle_AI#pbChooseMoves PokeBattle_Battler#pbUseMove
        PokeBattle_Battle#pbEndOfRoundPhase Graphics.update Game_Player#check_event_trigger_there
        PokemonEncounters#encounter_triggered? PokeBattle_Battler#pbFaint Object#pbBattleOnStepTaken
        PokeBattle_Move#pbCalcDamageMultipliers Sprite_Character#dispose PokemonEncounters#choose_wild_pokemon
        SaveData.save_to_file PokeBattle_Battler#pbProcessTurn PokemonBattlerSprite#update Spriteset_Map#update
        Object#pbEncounter PokemonStorageScene#pbUpdateOverlay PokemonGlobalMetadata#initialize
        PokeBattle_Scene#pbCommonAnimation Pokemon#ability2_id PokeBattle_Battler#pbEffectsOnSwitchIn PokemonBag#pbStoreItem
        PokeBattle_AI#pbGetMoveScoreFunctionCode PokeBattle_Battler#pbEffectsOnMakingHit PokeBattle_Battle#pbEndOfBattle
        Pokemon#ability_id GameData.load_all GameData::Item.held_icon_filename OverworldPokemonEvent#overworldPokemonBattle
        PokeBattle_Battle#pbCommandPhase PokeBattle_Battle#pbGainExp PokemonPartyScreen#pbPokemonScreen
        PokeBattle_Battle#pbCanMegaEvolve? Object#pbUnfuse PokemonSummary_Scene#pbStartScene PokeBattle_Move#pbCheckDamageAbsorption
        PokeBattle_Battler#pbInitEffects PokeBattle_Battler#pbChangeTargets PokeBattle_Move#pbNumHits Object#pbTrainerBattleCore
        Object#pbLoadTrainer Game.load PokeBattle_Battle#pbGainMoney
      ].freeze unless const_defined?(:SURVEY)

      # every method worth watching: the survey list, the event points, the hook targets
      def self.watched
        t = SURVEY.dup
        t.concat(Points.targets) if defined?(KIF::API::Points)
        t.concat(Hook.targets) if defined?(KIF::API::Hook)
        return t.uniq
      end

      # target text => [full source location or nil, original name, owner is the class itself]
      def self.snapshot
        out = {}
        watched.each do |t|
          r = Hook.resolve(t) rescue nil
          next unless r
          klass, name, single = r
          tc = single ? klass.singleton_class : klass
          um = (tc.instance_method(name) rescue nil)
          next unless um
          out[t] = [um.source_location, um.original_name, um.owner == tc]
        end
        return out
      end

      def self.before(mod); @snap[mod] ||= snapshot; end

      # a mod that wraps (`alias old m` + `def m`) leaves the old method reachable under another name
      def self.old_reachable?(tc, name, loc)
        (tc.instance_methods(false) + tc.private_instance_methods(false)).any? do |n|
          next false if n == name
          um = (tc.instance_method(n) rescue nil)
          um && um.source_location == loc
        end
      end

      # Compares with the snapshot taken before the mod's first file loaded.
      # Run after each file of the mod; cleared by forget_snapshots.
      def self.after(mod)
        old = @snap[mod]
        return [] unless old
        found = []
        snapshot.each do |t, now|
          was = old[t]
          next if was.nil? || was[0] == now[0]
          next unless now[0] && KIF::ModContract.owner_of_path(now[0][0]) == mod
          klass, name, single = Hook.resolve(t)
          tc = single ? klass.singleton_class : klass
          kind = (now[1] == name && now[2] && !old_reachable?(tc, name, was[0])) ? :replaced : :wrapped
          next if @list.any? { |e| e[:mod] == mod && e[:target] == t && e[:kind] == kind }
          @list.reject! { |e| e[:mod] == mod && e[:target] == t }
          entry = { :mod => mod, :target => t, :kind => kind, :was => was[0].to_a[0].to_s.sub(/\A.*Data\/Scripts\//, "") }
          found << entry
          @list << entry
          if kind == :replaced
            KIF.log("Mod #{Attribution.display(mod)} replaced #{t} (was #{entry[:was]}); wrappers made before it are bypassed")
          else
            KIF.verbose("Mod #{Attribution.display(mod)} wrapped #{t}")
          end
        end
        return found
      end

      def self.forget_snapshots; @snap.clear; end

      def self.list; return @list.dup; end
      def self.add(entry); @list << entry; end
      def self.clear; @list.clear; @snap.clear; end
    end

    # KIF::API.collisions -> [{ :mod, :target, :kind (:replaced | :wrapped | :bypassed), :was }]
    def self.collisions; return Collisions.list; end
  end
end
