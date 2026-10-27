#===============================================================================
# KIF Modules (2026-10-10)
#
# Every KIF / Cody's additions feature belongs to a module. Options > Modules sets each
# module to:
#   Off    - the feature does nothing: the game uses PIF's own behaviour, and
#            its settings, pause menu / PC entries are hidden
#   On     - the feature works and its settings page is shown
#   Hidden - the feature works, its settings page is hidden
# New players start with every module Off.
#
# How "Off" works without touching each feature: features are recognised by
# the folder their code lives in (MODULES below). This file
#   * records PIF's methods once the core has loaded (before any feature),
#   * wraps event callbacks and item/move handlers added from a module's
#     folder so they only run while the module is active;
# and ZZZ_Modules/ModuleGate.rb (loads after every feature) puts a switch in
# front of each method a module's code changed: Off -> the version the game
# had without that module (the method the feature aliased, PIF's original,
# or the parent class's), otherwise the feature's.
# KIF's own registries (settings, pause menu, PC actions) skip entries that
# come from an Off module.
#
# Always on (no module): the core, save compatibility, mod loading and mod
# compatibility, Mystery Gift, debug tools, settings presets, PIF fixes,
# map load cache, sprite import, save folder and the Cody's additions debug
# tools.
# Things a module changes while the game starts (data tables, constants)
# stay changed; their effects are listed in KIF_Features.md.
#===============================================================================
module KIF
  module Modules
    # id => [name, description, folder prefixes]
    MODULES = {
      :auto_battle  => ["Auto Battle",
                        "Auto-Battle and its options, Self-Battle from the PC.",
                        %w[F-BATTLE-02 F-PC-03]],
      :shinies      => ["Shinies",
                        "Shiny colours, shiny odds, shiny gamble, Poké Radar chains.",
                        %w[F-SHINY-01 F-SHINY-02 F-ITEM-04]],
      :graphics     => ["Graphical Changes",
                        "EBDX, battle box, effectiveness colours, icons, font, dark mode, title screen.",
                        %w[F-BATTLE-12 F-BATTLE-07 C-BATTLE-01 F-UI-02 F-UI-03 F-UI-11 F-UI-12 F-UI-14]],
      :information  => ["Information",
                        "Fusion preview and screen, Pokédex evolutions, IVs and EVs.",
                        %w[F-FUSION-03 C-FUSION-02 F-POKE-06 F-UI-04]],   # Battle Info: base feature
      :battles      => ["Battles & Challenges",
                        "Battle format, AI, challenges, level caps, EXP modes, gym teams.",
                        %w[F-BATTLE-01 F-BATTLE-03 F-BATTLE-04 F-BATTLE-05 F-BATTLE-06 F-BATTLE-08 F-BATTLE-09 F-BATTLE-10 F-BATTLE-11 C-GYM-01 C-BATTLE-02]],
      :randomizer   => ["Randomizer",
                        "The randomizer and gym leader teams.",
                        %w[C-RAND-01 C-GYM-01]],
      :pokemon      => ["Pokémon & Fusion",
                        "Fusion rules, breeding, evolution lock, gender, moves, types.",
                        %w[F-FUSION-01 F-FUSION-02 C-FUSION-01 F-POKE-01 F-POKE-02 F-POKE-03 F-POKE-04 F-POKE-05 F-POKE-08 F-DATA-01]],
      :items        => ["Kuray Shop",
                        "The Kuray Shop in the pause menu (and Streamer's Dream).",
                        %w[F-ITEM-01]],
      :keggs        => ["K-Eggs",
                        "K-Eggs: typed, badge, legendary and fusion eggs from the Kuray Shop.",
                        %w[F-ITEM-02]],
      :pc           => ["PC & Saves",
                        "PC extras, quicksave, eggs hatching into the PC.",
                        %w[F-PC-01 F-UI-06 F-UI-08]],   # F-CORE-03 Save Backups: always on (Off put back PIF's clean-up, which deletes named backups)
      :import       => ["Import & Export",
                        "Export Pokémon to files and import them back (PC and party).",
                        %w[F-PC-02]],
      :qol          => ["Quality of Life",
                        "Pause menu extras, field moves, speed-up, intro skip, shenanigans.",
                        %w[F-UI-01 F-UI-05 F-UI-07 F-UI-09 F-UI-10 SCOPE-04 C-SYS-02]],
      :mod_settings => ["Mod Settings",
                        "The Mods list in KIF Settings: switch mods On/Off, their settings.",
                        []]
    }
    OFF = 0
    ON = 1
    HIDDEN = 2
    # A module split out of another one later: a save that already has the
    # parent's state gets the same state for the new one
    SPLIT_FROM = { :keggs => :items, :import => :pc }
    STATE_NAMES = ["Off", "On", "Hidden"]

    @file_cache = {}
    @basenames = nil

    # The game evals each script with its bare file name ("AutoBattle.rb"), so
    # a bare name is looked up in KIF's own folder (names there are unique).
    def self.basename_map
      return @basenames if @basenames
      @basenames = {}
      dupes = {}
      root = KIF::Features.root
      Dir.glob(File.join(root, "**", "*.rb")).each do |f|
        b = File.basename(f)
        dupes[b] = true if @basenames.has_key?(b)
        @basenames[b] = f
      end
      dupes.each_key { |b| @basenames.delete(b) }
      return @basenames
    end

    # Module a source file belongs to (nil = always on)
    def self.for_file(path)
      return nil if path.nil?
      path = path.to_s
      return @file_cache[path] if @file_cache.has_key?(path)
      # Ruby's own code ("<internal:marshal>") is never a feature: no folder scan
      return @file_cache[path] = nil if path.start_with?("<")
      key = path
      # only .rb names are in the map
      path = basename_map[path] || path if path.end_with?(".rb") && !(path.include?("/") || path.include?("\\"))
      found = nil
      @module_res ||= MODULES.map { |id, (_n, _d, prefixes)|
        [id, prefixes.empty? ? nil : %r{(\A|[/\\])(?:#{prefixes.map { |pre| Regexp.escape(pre) }.join("|")})_}]
      }
      @module_res.each do |id, re|
        next unless re && path =~ re
        found = id
        break
      end
      @file_cache[key] = found
      return found
    end

    def self.for_proc(pr)
      return nil unless pr.respond_to?(:source_location)
      loc = pr.source_location
      return loc ? for_file(loc[0]) : nil
    end

    def self.states
      return nil unless $PokemonSystem && $PokemonSystem.respond_to?(:kif_modules)
      return $PokemonSystem.kif_modules
    end

    # A mod can set a module for as long as it's On (mod.json "modules",
    # KIF::Locks): that state wins over the player's, which is kept
    def self.state(id)
      return ON if id.nil?
      f = KIF::Locks.module_state(id)
      return f unless f.nil?
      h = states
      v = h ? h[id] : nil
      return v.nil? ? OFF : v
    end

    def self.set_state(id, value)
      h = states
      return unless h
      h[id] = value
      poll   # watchers (frame rate, species data...) follow at once
    end

    # id: a module (:battles), or a feature folder ("F-BATTLE-08_LevelCaps"):
    # a feature is active while its module is and no mod replaced it
    def self.active?(id)
      return true if id.nil?
      if id.is_a?(String)
        return false if KIF::Features.replaced?(id)
        ids = KIF::Features.modules_of(id)   # a folder listed in two modules runs while either is on
        return true if ids.empty?
        return ids.any? { |m| state(m) != OFF }
      end
      return state(id) != OFF
    end

    def self.visible?(id)
      return true if id.nil?
      if id.is_a?(String)
        return false if KIF::Features.replaced?(id)
        ids = KIF::Features.modules_of(id)   # a folder listed in two modules runs while either is on
        return true if ids.empty?
        return ids.any? { |m| state(m) == ON }
      end
      return state(id) == ON
    end

    # true when a proc (handler, builder...) belongs to an active module /
    # feature
    def self.proc_active?(pr);  return active?(KIF::Features.key_for_proc(pr) || for_proc(pr));  end
    def self.proc_visible?(pr); return visible?(KIF::Features.key_for_proc(pr) || for_proc(pr)); end

    # Blocks told when a module turns active / inactive (and once at start).
    # Not gated: they must also run when the module is turned off. A block
    # from a feature's own folder follows that feature (so it's also told
    # when a mod replaces the feature).
    @watchers = []
    @last = {}

    def self.watch(id, &block)
      key = KIF::Features.key_for_proc(block)
      id = key if key && KIF::Features.module_of(key) == id
      @watchers << [id, block]
    end

    def self.poll
      @watchers.each do |id, block|
        now = active?(id)
        next if @last.has_key?(block) && @last[block] == now
        @last[block] = now
        begin
          block.call(now)
        rescue => e
          KIF.log("Module #{id} change failed: #{e.class}: #{e.message}")
        end
      end
    end

    # Hooks that check a module themselves (the gate leaves them alone)
    @no_gate = {}
    def self.no_gate(mod); @no_gate[mod] = true; end
    def self.no_gate?(mod); return @no_gate[mod] ? true : false; end

    def self.all_on!
      h = states
      MODULES.each_key { |id| h[id] = ON } if h
    end

    #---------------------------------------------------------------------------
    # PIF's methods before any feature loads (used by ModuleGate for methods a
    # feature replaced without keeping the old one under another name)
    #---------------------------------------------------------------------------
    @snapshot = {}
    @snapshot_mods = {}
    class << self
      attr_reader :snapshot, :snapshot_mods
    end

    # The method a class itself defines. instance_method returns the method of
    # a module prepended to the class instead, so walk past those.
    def self.own_method(m, name)
      um = (m.instance_method(name) rescue nil)
      while um && um.owner != m
        um = (um.super_method rescue nil)
      end
      return um
    end

    @handler_snapshot = {}

    def self.take_snapshot
      # PIF's own item / move / battle handlers, for the ones a module replaces
      [HandlerHash, HandlerHash2, HandlerHashBasic].each do |k|
        ObjectSpace.each_object(k) do |o|
          h = o.instance_variable_get(:@hash)
          @handler_snapshot[o] = h.dup if h.is_a?(Hash)
        end
      end
      ObjectSpace.each_object(Module) do |mod|
        next if mod.singleton_class? rescue next
        [mod, mod.singleton_class].each do |m|
          @snapshot_mods[m] = true
          (m.instance_methods(false) + m.private_instance_methods(false)).each do |name|
            um = own_method(m, name)
            @snapshot[[m, name]] = um if um
          end
        end
      end
    end

    #---------------------------------------------------------------------------
    # Event callbacks and handler-hash entries from a module's folder only run
    # while that module is active.
    #---------------------------------------------------------------------------
    class GatedCallback
      attr_reader :mod_id, :callback, :fallback
      # fallback: what ran before the module's code replaced it (PIF's
      # handler), called while the module is Off; nil = nothing
      def initialize(mod_id, callback, fallback = nil)
        @mod_id = mod_id
        @callback = callback
        @fallback = fallback
      end
      def arity; @callback.arity; end
      def call(*args, &blk)
        unless KIF::Modules.active?(@mod_id)
          return @fallback ? @fallback.call(*args, &blk) : nil
        end
        @callback.call(*args, &blk)
      end
      def ==(other)
        return true if other.equal?(self)
        return other == @callback if other.is_a?(Proc) || other.is_a?(Method)
        return other.is_a?(GatedCallback) && other.callback == @callback
      end
      def source_location; @callback.source_location rescue nil; end
      def to_proc; method(:call).to_proc; end
    end

    # A handler hash entry must stay a real Proc: PIF's HandlerHash#add /
    # #copy refuse anything else, so a mod doing ItemHandlers.copy(:EXPCANDY,
    # ...) failed to load. The gate rides on the proc (gate_of).
    def self.gated_proc(g)
      pr = proc { |*args, &blk| g.call(*args, &blk) }
      pr.instance_variable_set(:@kif_gate, g)
      return pr
    end

    # the GatedCallback behind a handler (a gated proc or the callback itself)
    def self.gate_of(handler)
      return handler if handler.is_a?(GatedCallback)
      return handler.instance_variable_get(:@kif_gate) if handler.is_a?(Proc)
      return nil
    end

    def self.gate_callback(cb, fallback = nil)
      return cb if cb.is_a?(GatedCallback) || (cb.is_a?(Proc) && cb.instance_variable_get(:@kif_gate))
      id = KIF::Features.key_for_proc(cb) || for_proc(cb)
      return id ? GatedCallback.new(id, cb, fallback) : cb
    end

    # PIF's handler for a key before any module replaced it (nil if none)
    def self.pif_handler(hash_obj, key)
      snap = @handler_snapshot[hash_obj]
      return snap ? snap[key] : nil
    end
  end
end

#===============================================================================
# Features (2026-10-16): one folder of a module ("F-BATTLE-08_LevelCaps").
# A mod can replace one with its own version without turning the whole
# module Off:
#   mod.json   "replaces": ["F-BATTLE-08_LevelCaps"]
#   or Ruby    KIF::Features.replace("LevelCaps")
# While the mod is On, that folder's code acts as if its module were Off
# (PIF's behaviour, settings and menu entries hidden); the rest of the module
# keeps working. KIF::Features.list shows every feature a mod can replace.
# The core and the always-on parts (no module) can't be replaced.
#===============================================================================
module KIF
  module Features
    @file_keys = {}
    @module_of = {}
    @replaced = {}    # key => [mod name, mod id]

    # the module a feature folder belongs to (nil = always on / not a feature)
    def self.module_of(key)
      return @module_of[key] if @module_of.has_key?(key)
      found = nil
      KIF::Modules::MODULES.each do |id, (_n, _d, prefixes)|
        found = id if prefixes.any? { |pre| key.start_with?("#{pre}_") }
        break if found
      end
      return @module_of[key] = found
    end

    # every module a feature folder is listed in (usually one)
    def self.modules_of(key)
      @modules_of ||= {}
      return @modules_of[key] ||= KIF::Modules::MODULES.select { |_id, (_n, _d, prefixes)|
        prefixes.any? { |pre| key.start_with?("#{pre}_") } }.keys
    end

    # the feature a source file belongs to ("F-BATTLE-08_LevelCaps"), or nil
    def self.key_for_file(path)
      return nil if path.nil?
      path = path.to_s
      return @file_keys[path] if @file_keys.has_key?(path)
      key = nil
      if KIF::Modules.for_file(path)
        full = path
        full = KIF::Modules.basename_map[path] || path unless path.include?("/") || path.include?("\\")
        key = full.split(/[\/\\]/).find { |seg| module_of(seg) }
      end
      return @file_keys[path] = key
    end

    def self.key_for_proc(pr)
      return nil unless pr.respond_to?(:source_location)
      loc = (pr.source_location rescue nil)
      return loc ? key_for_file(loc[0]) : nil
    end

    # KIF's script folder (the game runs from its own folder; a test run
    # may not)
    HERE = (__FILE__.to_s.include?("/") || __FILE__.to_s.include?("\\")) ? File.expand_path(__FILE__.to_s) : nil
    def self.root
      return KIF.scripts_dir if KIF.respond_to?(:scripts_dir)
      dir = File.join("Data", "Scripts", "990_KIF")
      return dir if File.directory?(dir) || HERE.nil?
      return File.dirname(File.dirname(HERE))
    end

    # names the folder name doesn't spell out
    NAMES = {
      "F-BATTLE-09_ExpEvIvModes"   => "EXP, EV & IV Modes",
      "F-BATTLE-11_CatchQoL"       => "Catch QoL",
      "F-UI-01_QoLPauseMenu"       => "QoL Pause Menu",
      "F-UI-04_SummaryIVEV"        => "Summary IVs & EVs",
      "F-ITEM-04_PokeRadarPlus"    => "Poké Radar+",
      "F-POKE-06_ImprovedPokedex"  => "Improved Pokédex",
      "F-POKE-05_TutorNet"         => "Tutor.net",
      "F-UI-08_HatchToPC"          => "Hatch to PC",
      "F-UI-09_TitleAndLoad"       => "Title and Load Screens",
      "F-UI-10_Shenanigans"        => "Kuray's Shenanigans"
    }

    # "F-BATTLE-08_LevelCaps" -> "Level Caps"
    def self.title(key)
      return NAMES[key] if NAMES[key]
      return key.sub(/\A[A-Z]+(?:-[A-Z]+)?-\d+_/, "").gsub(/([a-z0-9])([A-Z])/, '\1 \2').gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
    end

    # Every feature a mod can replace:
    # [{:id => "F-BATTLE-08_LevelCaps", :name => "Level Caps",
    #   :module => :battles, :module_name => "Battles & Challenges"}, ...]
    def self.list
      return @list if @list
      out = []
      dirs = Dir.glob(File.join(root, "*")) + Dir.glob(File.join(root, "*", "*"))
      dirs.select { |d| File.directory?(d) }.map { |d| File.basename(d) }.uniq.sort.each do |key|
        mod = module_of(key)
        next unless mod
        out << { :id => key, :name => title(key), :module => mod,
                 :module_name => KIF::Modules::MODULES[mod][0] }
      end
      return @list = out
    end

    # "F-BATTLE-08_LevelCaps", "F-BATTLE-08", "LevelCaps" or "Level Caps" -> the id
    def self.resolve(name)
      name = name.to_s.strip
      return nil if name.empty?
      ids = list.map { |f| f[:id] }
      return name if ids.include?(name)
      flat = name.downcase.delete(" _-")
      hits = ids.select { |id| id.sub(/\A[A-Z]+(?:-[A-Z]+)?-\d+_/, "").downcase.delete(" _-") == flat }
      hits = ids.select { |id| id.start_with?("#{name}_") } if hits.empty?
      return hits.length == 1 ? hits[0] : nil
    end

    # by: the mod's name; owner: its id (both default to the mod whose
    # scripts are loading)
    def self.replace(name, by: nil, owner: nil)
      id = resolve(name)
      owner ||= (KIF::Mods.current if defined?(KIF::Mods) && KIF::Mods.respond_to?(:current))
      by ||= (KIF::Mods.display_name(owner) if owner && KIF::Mods.respond_to?(:display_name)) || owner || "A mod"
      unless id
        KIF.log("#{by}: can't replace \"#{name}\" - no KIF feature by that name (KIF::Features.list has them)")
        return false
      end
      if @replaced[id] && @replaced[id][1] != owner
        KIF.log("#{by}: #{id} is already replaced by #{@replaced[id][0]} - left to it")
        return false
      end
      @replaced[id] = [by.to_s, owner]
      KIF.log("#{by} replaces KIF's #{title(id)} (#{id})")
      return true
    end

    # undo what a mod replaced (a mod that failed to load)
    def self.release(owner)
      @replaced.delete_if { |_k, v| v[1] == owner }
    end

    def self.replaced?(key)
      return false if @replaced.empty?
      return @replaced.has_key?(key)
    end

    def self.replaced_by(key); return @replaced[key] ? @replaced[key][0] : nil; end

    # the features one mod replaced
    def self.owned_by(owner)
      return @replaced.select { |_k, v| v[1] == owner }.keys
    end
    # key => mod name
    def self.replacements; return @replaced.map { |k, v| [k, v[0]] }.to_h; end

    def self.reset!
      @replaced = {}
    end
  end
end

KIF::Options.define(:kif_modules, {}, :global)

# Players who were already playing KIF before Modules existed keep their
# features: a save from before Modules turns every module On once. New
# players (no save yet) start with everything Off.
module Game
  class << self
    alias kif_modules_set_up_system set_up_system unless method_defined?(:kif_modules_set_up_system)
    def set_up_system
      kif_modules_set_up_system
      KIF::Modules.migrate_old_save
    end
  end
end

module KIF
  module Modules
    # also run when saves copied from old KIF are read at first launch
    # (C-SYS-05), so those players aren't asked how to play
    def self.migrate_old_save
      if $PokemonSystem && !$PokemonSystem.instance_variable_defined?(:@kif_modules) && SaveData.exists?
        all_on!
        KIF.log("Modules: save from before Modules - every module turned On")
      end
      inherit_split_states
    rescue => e
      KIF.log("Modules: migration failed (#{e.class}: #{e.message})")
    end
  end
end

module KIF
  module Modules
    def self.inherit_split_states
      h = states
      return unless h && !h.empty?
      SPLIT_FROM.each do |id, parent|
        next if h.has_key?(id) || !h.has_key?(parent)
        h[id] = h[parent]
        KIF.log("Modules: #{MODULES[id][0]} takes #{MODULES[parent][0]}'s state (#{STATE_NAMES[h[id]] rescue h[id]})")
      end
    end
  end
end


class Event
  alias kif_mod_event_add + unless method_defined?(:kif_mod_event_add)
  def +(method)
    return kif_mod_event_add(KIF::Modules.gate_callback(method))
  end
end

# Handler hashes (ItemHandlers, MoveHandlers ...): wrap procs added from a
# module's folder. Done once after every feature has loaded (ModuleGate),
# since they are added at load time.
module KIF
  module Modules
    def self.gate_handler_hashes
      n = 0
      objs = []
      [HandlerHash, HandlerHash2, HandlerHashBasic].each do |k|
        ObjectSpace.each_object(k) { |o| objs << o }
      end
      objs.uniq.each do |obj|
        h = obj.instance_variable_get(:@hash)
        next unless h.is_a?(Hash)
        snap = @handler_snapshot[obj] || {}
        h.each do |k, v|
          next unless v.respond_to?(:call) && v.respond_to?(:source_location)
          fb = snap[k]
          fb = nil if fb.equal?(v)
          g = gate_callback(v, fb)
          next if g.equal?(v)
          h[k] = gated_proc(g)
          n += 1
        end
        ifs = obj.instance_variable_get(:@addIfs) || obj.instance_variable_get(:@add_ifs)
        if ifs.is_a?(Array)
          ifs.each do |entry|
            next unless entry.is_a?(Array)
            entry.each_with_index do |v, i|
              next unless v.is_a?(Proc)
              g = gate_callback(v)
              next if g.equal?(v)
              entry[i] = gated_proc(g)
              n += 1
            end
          end
        end
      end
      return n
    end
  end
end

# Watchers run before a save is loaded too (data a module changes must be in
# its right state before anything reads it), then once per map frame.
module Game
  class << self
    alias kif_modules_load load unless method_defined?(:kif_modules_load)
    def load(*args, &blk)
      KIF::Modules.poll
      ret = kif_modules_load(*args, &blk)
      # a mod's locked stat rules (Max IVs, No EVs...) apply to stats saved without them
      KIF.recalc_all_stats if defined?(KIF::Locks) && KIF::Locks.any?
      ret
    end
  end
end

class Scene_Map
  alias kif_modules_update update unless method_defined?(:kif_modules_update)
  def update
    KIF::Modules.poll
    kif_modules_update
  end
end

KIF::Modules.take_snapshot
