#===============================================================================
# KIF Modules (Cody, 2026-10-10)
#
# Every KIF / Cody feature belongs to a module. Options > Modules sets each
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
# map load cache, sprite import, save folder and Cody's debug tools.
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
                        "EBDX, battle box, effectiveness colours, icons, font, dark mode.",
                        %w[F-BATTLE-12 F-BATTLE-07 C-BATTLE-01 F-UI-02 F-UI-03 F-UI-11]],
      :information  => ["Information",
                        "Fusion preview and screen, Pokédex evolutions, IVs and EVs.",
                        %w[F-FUSION-03 C-FUSION-02 F-POKE-06 F-UI-04]],
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
                        "PC extras, quicksave, save backups, eggs hatching into the PC.",
                        %w[F-PC-01 F-UI-06 F-CORE-03 F-UI-08]],
      :import       => ["Import & Export",
                        "Export Pokémon to files and import them back (PC and party).",
                        %w[F-PC-02]],
      :qol          => ["Quality of Life",
                        "Pause menu extras, field moves, speed-up, intro skip, shenanigans.",
                        %w[F-UI-01 F-UI-05 F-UI-07 F-UI-09 F-UI-10 SCOPE-04 C-SYS-02]],
      :mod_settings => ["Mod Settings",
                        "Shows the settings of your Mod Manager mods here.",
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
      root = KIF.respond_to?(:scripts_dir) ? KIF.scripts_dir : nil
      root ||= File.join("Data", "Scripts", "990_KIF")
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
      key = path
      path = basename_map[path] || path unless path.include?("/") || path.include?("\\")
      found = nil
      MODULES.each do |id, (_n, _d, prefixes)|
        prefixes.each do |pre|
          if path =~ %r{(\A|[/\\])#{Regexp.escape(pre)}_}
            found = id
            break
          end
        end
        break if found
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

    def self.state(id)
      return ON if id.nil?
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

    def self.active?(id);  return id.nil? || state(id) != OFF; end
    def self.visible?(id); return id.nil? || state(id) == ON;  end

    # true when a proc (handler, builder...) belongs to an active module
    def self.proc_active?(pr);  return active?(for_proc(pr));  end
    def self.proc_visible?(pr); return visible?(for_proc(pr)); end

    # Blocks told when a module turns active / inactive (and once at start).
    # Not gated: they must also run when the module is turned off.
    @watchers = []
    @last = {}

    def self.watch(id, &block)
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

    def self.gate_callback(cb, fallback = nil)
      return cb if cb.is_a?(GatedCallback)
      id = for_proc(cb)
      return id ? GatedCallback.new(id, cb, fallback) : cb
    end

    # PIF's handler for a key before any module replaced it (nil if none)
    def self.pif_handler(hash_obj, key)
      snap = @handler_snapshot[hash_obj]
      return snap ? snap[key] : nil
    end
  end
end

KIF::Options.define(:kif_modules, {}, :global)

# Players who were already playing KIF Beta before Modules existed keep their
# features: a save from before Modules turns every module On once. New
# players (no save yet) start with everything Off.
module Game
  class << self
    alias kif_modules_set_up_system set_up_system unless method_defined?(:kif_modules_set_up_system)
    def set_up_system
      kif_modules_set_up_system
      begin
        if $PokemonSystem && !$PokemonSystem.instance_variable_defined?(:@kif_modules) && SaveData.exists?
          KIF::Modules.all_on!
          KIF.log("Modules: save from before Modules - every module turned On")
        end
        KIF::Modules.inherit_split_states
      rescue => e
        KIF.log("Modules: migration failed (#{e.class}: #{e.message})")
      end
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
          h[k] = g
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
              entry[i] = g
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
      kif_modules_load(*args, &blk)
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
