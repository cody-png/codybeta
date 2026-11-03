#===============================================================================
# F-CORE-10 Mod API - registries: content a mod adds without copying game code
#
# Every call remembers which mod made it (so the inspector can show it and a
# reload can take it back). Anything that needs the game's data (items,
# evolutions, encounters, texts) is queued and applied by one DataLoad step,
# "ModAPI registries", and again after every GameData.load_all.
#
#   KIF::API::PauseMenu.add(:my_row, "My row", handler: ->(scene) { ...; :stay }, condition: -> { true }, order: 100)
#   KIF::API::PauseMenu.hide(:kif_pc) / relabel(:kif_pc, "Box") / move(:kif_pc, 5) / remove(:my_row)
#   KIF::API::PartyMenu.add(:my_row, "My action", handler: ->(screen, pkmn, idx) { })
#   KIF::API::BattlerState.register("rage", 0, reset_on: :switch_in)   # :switch_in | :battle_end | :never
#   KIF::API::BattlerState.set(battler, "rage", 3); .get(battler, "rage")
#   KIF::API::Shops.add(:PEWTER, [:ETHER]) / .add(:all, [:POTION], if: ->(ctx) { true })
#   KIF::API::Shops.add_kuray(:MYITEM, 5000, 2500, false)
#   KIF::API::Items.register(:MYSTONE, name: "My Stone", description: "...", price: 1000,
#                            icon: "icons/mystone.png" | { item: :OTHER }, handlers: { use_on_pokemon: proc { } })
#   KIF::API::Tune.set("Pokemon::EV_LIMIT", 999)  /  Tune.revert(mod)
#   KIF::API::AI.score("id", priority: KIF::API::LATE) { |ctx| ctx[:score] += 10 }
#   KIF::API::Fusion.after("id") { |ctx| ... }
#   KIF::API::Text.swap("Some game text") { "Other text" }  / Text.set(:item_name, :POTION, "Tonic")
#   KIF::API::Encounters.rate("id") { |ctx| ctx[:result] = true }
#   KIF::API::Encounters.add_slot(map: 5, type: :Land, species: :PIKACHU, min_level: 3, max_level: 5, chance: 10)
#   KIF::API::Evolutions.register_method(:MyMethod, hash) / Evolutions.add(:RATTATA, to: :RATICATE, method: :Level, parameter: 20)
#   KIF::API::Sprites.decorate(:character) { |sprite, character| } / .on_dispose { |sprite, character| }
#   KIF::API::Theme.color(:acc) / register_color("name", [r, g, b]);  KIF::API::Fonts.available
#===============================================================================
module KIF
  module API
    module Registries
      @owned   ||= { :pause => {}, :party => {}, :shops => {}, :text => {} }   # kind => { id => mod }
      @items   ||= {}     # Symbol => { :mod, :opts }
      @applied ||= {}     # item Symbol => id_number we gave it
      @icons   ||= {}     # item Symbol => { :mod, :icon, :held }
      @edits   ||= {}     # pause menu id => { :hide, :label, :order, :mod }
      @states  ||= {}     # "mod/key" => { :default, :reset_on }
      @text    ||= {}     # [kind, id] => { :mod, :text }
      @evos    ||= []     # [mod, species, to, method, parameter]
      @slots   ||= []     # { :mod, :map, ... }
      @evo_methods ||= {} # id => { :mod, :hash }
      @gen     ||= Hash.new(0)   # mod => generation (a text swap of an unloaded mod stays quiet)
      @tuned   ||= {}     # "Owner::CONST" => [[mod, old, new], ...]
      @colors  ||= {}
      @hooked  ||= {}

      class << self
        attr_reader :items, :applied, :states, :text, :slots, :evos, :edits, :tuned, :owned, :icons
      end

      def self.key(locs); return Attribution.key_from_caller(locs); end

      def self.data_ready?
        return defined?(GameData::Item) && GameData::Item.respond_to?(:exists?) && GameData::Item.exists?(:POTION)
      rescue StandardError
        return false
      end

      def self.bad(mod, what)
        API.say("reg:#{mod}:#{what}", "Mod \"#{Attribution.display(mod)}\": #{what}")
        raise ArgumentError, what if API.dev?
        return nil
      end

      #-------------------------------------------------------------------------
      # Applying what needs the game's data
      #-------------------------------------------------------------------------
      def self.apply_data
        apply_items
        apply_evolution_methods
        apply_evolutions
        apply_slots
        apply_text
      end

      def self.apply_items
        return unless data_ready?
        used = {}
        top = 0
        GameData::Item.each do |it|
          next if @applied.key?(it.id)
          used[it.id_number] = true
          top = it.id_number if it.id_number > top
        end
        n = top
        @items.sort_by { |id, e| [e[:mod].to_s, id.to_s] }.each do |id, e|
          o = e[:opts]
          if GameData::Item.exists?(id) && !@applied.key?(id)
            API.say("itemclash:#{id}", "Mod \"#{Attribution.display(e[:mod])}\": item :#{id} already exists, not registered")
            next
          end
          num = o[:number]
          if num.is_a?(Integer) && num > 0 && !used[num]
            # an explicit number that is free is kept
          else
            if num.is_a?(Integer)
              API.say("itemnum:#{id}", "Mod \"#{Attribution.display(e[:mod])}\": item number #{num} of :#{id} is taken, using a free one")
            end
            n += 1 while used[n + 1]
            n += 1
            num = n
          end
          used[num] = true
          row = { :id => id, :id_number => num, :name => o[:name], :name_plural => o[:name_plural] || (o[:name] + "s"),
                  :pocket => o[:pocket], :price => o[:price], :description => o[:description],
                  :field_use => o[:field_use], :battle_use => o[:battle_use], :type => o[:type] }
          row[:move] = o[:move] if o[:move]
          GameData::Item.register(row)
          MessageTypes.set(MessageTypes::Items, num, o[:name])
          MessageTypes.set(MessageTypes::ItemPlurals, num, row[:name_plural])
          MessageTypes.set(MessageTypes::ItemDescriptions, num, o[:description])
          @applied[id] = num
          add_handlers(id, o[:handlers])
        end
      rescue StandardError => e
        KIF.log("ModAPI registries: items failed (#{e.class}: #{e.message[0, 120]})")
      end

      HANDLER_HASHES = { :use_on_pokemon => "UseOnPokemon", :use_in_field => "UseInField", :use_from_bag => "UseFromBag",
                         :use_in_battle => "UseInBattle", :can_use_in_battle => "CanUseInBattle" }.freeze unless const_defined?(:HANDLER_HASHES)

      def self.add_handlers(id, handlers)
        return unless handlers.is_a?(Hash)
        handlers.each do |k, pr|
          name = HANDLER_HASHES[k.to_sym]
          next unless name && pr.respond_to?(:call) && ItemHandlers.const_defined?(name)
          ItemHandlers.const_get(name).add(id, pr)
        end
      end

      def self.apply_evolution_methods
        return unless defined?(GameData::Evolution)
        @evo_methods.each do |id, e|
          next if GameData::Evolution::DATA.key?(id)
          GameData::Evolution.register(e[:hash].merge(:id => id))
        end
      rescue StandardError => e
        KIF.log("ModAPI registries: evolution methods failed (#{e.class}: #{e.message[0, 120]})")
      end

      def self.apply_evolutions
        return if @evos.empty? || !(defined?(GameData::Species) && GameData::Species.respond_to?(:exists?) && GameData::Species.exists?(:BULBASAUR))
        changed = false
        @evos.each do |mod, species, to, meth, param|
          unless GameData::Species.exists?(species) && GameData::Species.exists?(to)
            API.say("evo:#{species}:#{to}", "Mod \"#{Attribution.display(mod)}\": evolution #{species} -> #{to}: a species does not exist")
            next
          end
          from = GameData::Species.get(species)
          tgt = GameData::Species.get(to)
          next if from.evolutions.any? { |ev| ev[0] == tgt.species && ev[1] == meth && ev[2] == param && !ev[3] }
          from.evolutions << [tgt.species, meth, param, false]
          tgt.evolutions << [from.species, meth, param, true] unless tgt.evolutions.any? { |ev| ev[3] && ev[0] == from.species }
          changed = true
        end
        KIF::Perf.bump_token if changed && defined?(KIF::Perf) && KIF::Perf.respond_to?(:bump_token)
      rescue StandardError => e
        KIF.log("ModAPI registries: evolutions failed (#{e.class}: #{e.message[0, 120]})")
      end

      def self.apply_slots
        return unless defined?(GameData::Encounter)
        @slots.each do |s|
          next unless GameData::Species.exists?(s[:species])
          enc = GameData::Encounter::DATA[:"#{s[:map]}_0"]
          unless enc
            enc = GameData::Encounter.new({ :id => :"#{s[:map]}_0", :map => s[:map], :version => 0, :step_chances => {}, :types => {} })
            GameData::Encounter::DATA[enc.id] = enc
          end
          list = (enc.types[s[:type]] ||= [])
          row = [s[:chance], s[:species], s[:min_level], s[:max_level]]
          list << row unless list.include?(row)
          enc.step_chances[s[:type]] ||= 25 if enc.step_chances.is_a?(Hash)
        end
      rescue StandardError => e
        KIF.log("ModAPI registries: encounter slots failed (#{e.class}: #{e.message[0, 120]})")
      end

      TEXT_KINDS = { :item_name => :Items, :item_description => :ItemDescriptions, :item_plural => :ItemPlurals,
                     :map_name => :MapNames, :type_name => :Types }.freeze unless const_defined?(:TEXT_KINDS)

      def self.apply_text
        @text.each do |(kind, id), e|
          type = TEXT_KINDS[kind]
          next unless type && MessageTypes.const_defined?(type)
          num = case kind
                when :map_name then id.to_i
                when :type_name then (GameData::Type.get(id).id_number rescue nil)
                else (GameData::Item.get(id).id_number rescue nil)
                end
          next unless num
          MessageTypes.set(MessageTypes.const_get(type), num, e[:text])
        end
      rescue StandardError => e
        KIF.log("ModAPI registries: texts failed (#{e.class}: #{e.message[0, 120]})")
      end

      def self.remove_mod(key)
        @items.delete_if { |_, e| e[:mod] == key }
        @icons.delete_if { |_, e| e[:mod] == key }
        @edits.delete_if { |_, e| e[:mod] == key }
        @states.delete_if { |_, e| e[:mod] == key }
        @text.delete_if { |_, e| e[:mod] == key }
        @evos.reject! { |e| e[0] == key }
        @slots.reject! { |e| e[:mod] == key }
        @evo_methods.delete_if { |_, e| e[:mod] == key }
        @gen[key] += 1
        @owned[:pause].select { |_, m| m == key }.keys.each { |id| KIF::PauseMenu.instance_variable_get(:@entries).reject! { |e| e.id == id }; @owned[:pause].delete(id) }
        @owned[:party].select { |_, m| m == key }.keys.each { |id| KIF::PartyMenu.remove(id); @owned[:party].delete(id) }
        Tune.revert(key)
      end

      # KIF's step: after KIF's own data steps, before the mods'
      STEP = "ModAPI registries" unless const_defined?(:STEP)
      if defined?(KIF::DataLoad) && !(KIF::DataLoad.instance_variable_get(:@hooks) || []).any? { |n, _| n == STEP }
        KIF::DataLoad.after_load_all(STEP) { KIF::API::Registries.apply_data }
      end
    end

    on_unload(:registries) { |key| Registries.remove_mod(key) }

    #---------------------------------------------------------------------------
    # Pause menu
    #---------------------------------------------------------------------------
    module PauseMenu
      # KIF::API::PauseMenu.add(id, label, condition: nil, handler:, icon: nil, order: 100)
      # = KIF::PauseMenu.add with the mod remembered. The handler gets the scene and
      # returns :stay (the menu comes back) or :close. A row that raises is skipped.
      def self.add(id, label, condition: nil, handler:, icon: nil, order: 100)
        key = Registries.key(caller_locations(1, 40))
        Registries.owned[:pause][id] = key
        KIF::PauseMenu.add(id, label, condition: condition, handler: handler, icon: icon, order: order)
        return id
      end

      def self.remove(id)
        KIF::PauseMenu.instance_variable_get(:@entries).reject! { |e| e.id == id }
        Registries.owned[:pause].delete(id)
        return true
      end

      def self.edit(id, what, value, locs)
        key = Registries.key(locs)
        Registries.edits[id] = (Registries.edits[id] || {}).merge(what => value, :mod => key)
        API.on(:pause_menu_build, "modapi_pause_edits", mod: :kif) { |ctx| Registries.apply_pause_edits(ctx) }
        return id
      end

      # persistent edits of any row (KIF's own included), applied each time the menu is built
      def self.hide(id); edit(id, :hide, true, caller_locations(1, 40)); end
      def self.relabel(id, text); edit(id, :label, text, caller_locations(1, 40)); end
      def self.move(id, order); edit(id, :order, order, caller_locations(1, 40)); end
    end

    module Registries
      def self.apply_pause_edits(ctx)
        @edits.each do |id, e|
          next if API.mod_off?(e[:mod])
          if e[:hide] then ctx.hide(id) else
            ctx.relabel(id, e[:label]) if e[:label]
            ctx.move(id, e[:order]) if e[:order]
          end
        end
      end
    end

    #---------------------------------------------------------------------------
    # Party menu: a row in the field "Do what with X?" list (KIF::PartyMenu)
    #---------------------------------------------------------------------------
    module PartyMenu
      def self.add(id, label, handler:, condition: nil, order: 100)
        key = Registries.key(caller_locations(1, 40))
        Registries.owned[:party][id] = key
        KIF::PartyMenu.add(id, label, handler: handler, condition: condition, order: order)
        return id
      end

      def self.remove(id)
        KIF::PartyMenu.remove(id)
        Registries.owned[:party].delete(id)
        return true
      end
    end

    #---------------------------------------------------------------------------
    # Per-battler state: replaces an alias of pbInitEffects for every mod
    #---------------------------------------------------------------------------
    module BattlerState
      # register(key, default, reset_on: :switch_in | :battle_end | :never)
      #   :switch_in  reset when the battler enters (a Baton Pass keeps it)
      #   :battle_end / :never  kept until the battle ends (everything is cleared then)
      def self.register(key, default, reset_on: :switch_in)
        mod = Registries.key(caller_locations(1, 40))
        unless [:switch_in, :battle_end, :never].include?(reset_on)
          return Registries.bad(mod, "BattlerState reset_on must be :switch_in, :battle_end or :never")
        end
        Registries.states[full(mod, key)] = { :default => default, :reset_on => reset_on, :mod => mod }
        API.on(:battler_init, "modapi_battler_state", mod: :kif) { |ctx| BattlerState.init(ctx) }
        API.on(:battle_ended, "modapi_battler_state", mod: :kif) { |ctx| BattlerState.clear(ctx) }
        return true
      end

      def self.full(mod, key); return "#{mod}/#{key}"; end

      def self.get(battler, key)
        mod = Registries.key(caller_locations(1, 40))
        k = full(mod, key)
        spec = Registries.states[k]
        return nil unless spec
        st = battler.instance_variable_get(:@kifapi_state)
        return st[k] if st && st.key?(k)
        d = spec[:default]
        return (d.is_a?(Array) || d.is_a?(Hash) || d.is_a?(String)) ? Marshal.load(Marshal.dump(d)) : d
      end

      def self.set(battler, key, value)
        mod = Registries.key(caller_locations(1, 40))
        k = full(mod, key)
        unless Registries.states[k]
          return Registries.bad(mod, "BattlerState key #{key.inspect} is not registered (BattlerState.register first)")
        end
        st = battler.instance_variable_get(:@kifapi_state)
        st = battler.instance_variable_set(:@kifapi_state, {}) unless st
        st[k] = value
      end

      def self.init(ctx)
        st = ctx[:battler].instance_variable_get(:@kifapi_state)
        return unless st
        Registries.states.each { |k, spec| st.delete(k) if spec[:reset_on] == :switch_in && !ctx[:baton_pass] }
      end

      def self.clear(ctx)
        b = ctx[:battle]
        list = b.respond_to?(:battlers) ? b.battlers : []
        list.each { |x| x.remove_instance_variable(:@kifapi_state) if x && x.instance_variable_defined?(:@kifapi_state) }
      end
    end

    #---------------------------------------------------------------------------
    # Shops
    #---------------------------------------------------------------------------
    module Shops
      # add(shop, items, if: nil): shop is a city Symbol (:PEWTER) or :all; if: a proc(ctx) -> true/false
      def self.add(shop, items, **opts)
        key = Registries.key(caller_locations(1, 40))
        list = Array(items).map { |i| i.to_sym }
        cond = opts[:if]
        sh = shop.to_s.upcase
        API.on(:shop_stock, "shops:#{sh}:#{list.join(',')}", mod: key) do |ctx|
          next if sh != "ALL" && ctx[:city].to_s.upcase != sh
          next if cond && !cond.call(ctx)
          cur = Array(ctx[:result])
          ctx[:result] = cur + list.reject { |i| cur.include?(i) }
        end
        return true
      end

      # add_kuray(item, buy, sell, free_with_dream = false): a row in the Kuray Shop (once per item)
      def self.add_kuray(item, buy, sell, free_with_dream = false)
        key = Registries.key(caller_locations(1, 40))
        return Registries.bad(key, "the Kuray Shop is not loaded") unless defined?(KIF::KurayShop::ITEMS)
        return false if KIF::KurayShop::ITEMS.any? { |r| r[0] == item }
        KIF::KurayShop::ITEMS << (free_with_dream ? [item, buy, sell, true] : [item, buy, sell])
        return true
      end
    end

    #---------------------------------------------------------------------------
    # Items
    #---------------------------------------------------------------------------
    module Items
      DEFAULTS = { :name_plural => nil, :price => 0, :pocket => 1, :field_use => 0, :battle_use => 0, :type => 0,
                   :move => nil, :icon => nil, :held_icon => nil, :number => :auto, :handlers => {} }.freeze unless const_defined?(:DEFAULTS)

      def self.register(id, name:, description:, **opts)
        mod = Registries.key(caller_locations(1, 40))
        id = id.to_s.upcase.to_sym
        return Registries.bad(mod, "item id #{id.inspect} must be letters, digits and _") unless id.to_s =~ /\A[A-Z][A-Z0-9_]{0,40}\z/
        return Registries.bad(mod, "item :#{id} needs a name") if name.to_s.strip.empty?
        o = DEFAULTS.merge(opts).merge(:name => name.to_s, :description => description.to_s)
        old = Registries.items[id]
        return Registries.bad(mod, "item :#{id} is already registered by #{Attribution.display(old[:mod])}") if old && old[:mod] != mod
        Registries.items[id] = { :mod => mod, :opts => o }
        if o[:icon] || o[:held_icon]
          Registries.icons[id] = { :mod => mod, :icon => o[:icon], :held => o[:held_icon] }
          Registries.hook_icons
        end
        Registries.apply_items if Registries.data_ready?
        return id
      end
    end

    module Registries
      def self.hook_icons
        return if @hooked[:icons]
        @hooked[:icons] = true
        Hook.attach(:around, GameData::Item, :icon_filename, true, "reg:icon", -400, nil, proc { |call| Registries.icon_hook(call, :icon) }, true)
        Hook.attach(:around, GameData::Item, :held_icon_filename, true, "reg:held_icon", -400, nil, proc { |call| Registries.icon_hook(call, :held) }, true)
      end

      def self.icon_hook(call, kind)
        it = (GameData::Item.try_get(call.args[0]) rescue nil)
        e = it ? @icons[it.id] : nil
        v = e ? (e[kind] || (kind == :held ? e[:icon] : nil)) : nil
        return call.proceed unless v
        if v.is_a?(Hash) && v[:item]
          return GameData::Item.send(kind == :held ? :held_icon_filename : :icon_filename, v[:item])
        end
        info = API.mod(e[:mod])
        path = info && info.path ? File.join(info.path.to_s, v.to_s) : nil
        return call.proceed unless path
        base = path.sub(/\.(png|gif|jpg)\z/i, "")
        return base if File.file?(path) || File.file?(base + ".png")
        return call.proceed
      end
    end

    #---------------------------------------------------------------------------
    # Constants: KIF::API::Tune.set("Pokemon::EV_LIMIT", 999)
    #---------------------------------------------------------------------------
    module Tune
      PLAIN = [Numeric, String, Symbol, Array, Hash, TrueClass, FalseClass].freeze unless const_defined?(:PLAIN)

      def self.parse(name)
        parts = name.to_s.split("::")
        return nil if parts.length < 2
        const = parts.pop
        owner = (Object.const_get(parts.join("::")) rescue nil)
        return nil unless owner.is_a?(Module) && const =~ /\A[A-Z][A-Za-z0-9_]*\z/
        return [owner, const.to_sym]
      end

      # Replaces a plain constant (Numeric, String, Symbol, Array, Hash, true/false). Code
      # that read the old value earlier keeps it. Classes and modules are refused.
      def self.set(name, value)
        mod = Registries.key(caller_locations(1, 40))
        owner, const = parse(name)
        return Registries.bad(mod, "Tune.set: #{name} is not a constant (use \"Owner::NAME\")") unless owner
        full = "#{owner.name}::#{const}"
        return Registries.bad(mod, "Tune.set: #{full} can not be changed") if full =~ /\AKIF::(Mod|Safe|API|Contract)/ || owner.name =~ /\AKIF::(ModGuard|ModTrust|Safe|ModContract|API)/
        return Registries.bad(mod, "Tune.set: #{full} does not exist") unless owner.const_defined?(const, false)
        old = owner.const_get(const)
        return Registries.bad(mod, "Tune.set: #{full} is a #{old.class}, only plain values can be tuned") if old.is_a?(Module)
        return Registries.bad(mod, "Tune.set: the new value must be plain (#{PLAIN.map(&:name).join(', ')})") unless PLAIN.any? { |k| value.is_a?(k) } && !value.is_a?(Module)
        (Registries.tuned[full] ||= []) << [mod, old, value]
        replace(owner, const, value)
        KIF.log("Mod #{Attribution.display(mod)} changed #{full} from #{old.inspect[0, 40]} to #{value.inspect[0, 40]} (code that read it earlier keeps the old value)")
        return true
      end

      def self.replace(owner, const, value)
        v = $VERBOSE
        $VERBOSE = nil
        owner.send(:remove_const, const)
        owner.const_set(const, value)
      ensure
        $VERBOSE = v
      end

      # Puts back what the mod changed. The newest change gives the constant back its
      # value from before; a change under a later mod's keeps that mod's value.
      def self.revert(mod)
        Registries.tuned.each do |full, stack|
          owner, const = parse(full)
          while (i = stack.rindex { |m, _o, _n| m == mod })
            entry = stack[i]
            if i == stack.length - 1
              replace(owner, const, i > 0 ? stack[i - 1][2] : entry[1]) if owner
              KIF.log("Tune: #{full} put back (mod #{Attribution.display(mod)} unloaded)")
            else
              stack[i + 1][1] = entry[1]   # the next mod's "before" is now this mod's
            end
            stack.delete_at(i)
          end
        end
        Registries.tuned.delete_if { |_, s| s.empty? }
      end
    end

    #---------------------------------------------------------------------------
    # Sugar: names for the events mods use most
    #---------------------------------------------------------------------------
    module AI
      # score(id = nil, priority: 0) { |ctx| ctx[:score] += 10 } = on(:ai_score_move).
      # PIF's scores are absolute; a DemICE-style AI returns changes: add to ctx[:score].
      def self.score(id = nil, priority: 0, &blk)
        return API.on(:ai_score_move, id, priority: priority, mod: Registries.key(caller_locations(1, 40)), &blk)
      end
    end

    module Fusion
      def self.after(id = nil, priority: 0, &blk)
        return API.on(:fusion_done, id, priority: priority, mod: Registries.key(caller_locations(1, 40)), &blk)
      end
    end

    module Encounters
      def self.rate(id = nil, priority: 0, &blk)
        return API.on(:encounter_roll, id, priority: priority, mod: Registries.key(caller_locations(1, 40)), &blk)
      end

      # add_slot(map:, type: :Land, species:, min_level:, max_level:, chance:)
      def self.add_slot(map:, species:, min_level:, max_level:, chance:, type: :Land)
        mod = Registries.key(caller_locations(1, 40))
        ok = map.is_a?(Integer) && chance.is_a?(Integer) && chance > 0 && min_level.is_a?(Integer) && max_level.is_a?(Integer) && min_level.between?(1, 100) && max_level.between?(min_level, 100)
        return Registries.bad(mod, "Encounters.add_slot needs an Integer map, chance, and levels 1..100") unless ok
        Registries.slots << { :mod => mod, :map => map, :type => type.to_sym, :species => species.to_sym, :min_level => min_level, :max_level => max_level, :chance => chance }
        Registries.apply_slots if Registries.data_ready?
        return true
      end
    end

    module Evolutions
      # register_method(id, hash): a new evolution method (keys as in 010_Data/001_Hardcoded data/007_Evolution.rb)
      def self.register_method(id, hash)
        mod = Registries.key(caller_locations(1, 40))
        return Registries.bad(mod, "Evolutions.register_method needs a Hash") unless hash.is_a?(Hash)
        Registries.instance_variable_get(:@evo_methods)[id.to_sym] = { :mod => mod, :hash => hash }
        Registries.apply_evolution_methods if Registries.data_ready?
        return true
      end

      # add(species, to:, method:, parameter: nil): species can evolve into `to`
      def self.add(species, to:, method:, parameter: nil)
        mod = Registries.key(caller_locations(1, 40))
        Registries.evos << [mod, species.to_sym, to.to_sym, method.to_sym, parameter]
        Registries.apply_evolutions
        return true
      end
    end

    module Text
      # swap("Some game text") { "other text" or nil } = KIF::TextSwap.add for this mod
      def self.swap(original, &blk)
        mod = Registries.key(caller_locations(1, 40))
        raise ArgumentError, "Text.swap needs a block" unless blk
        gens = Registries.instance_variable_get(:@gen)
        g = gens[mod]
        KIF::TextSwap.add(original) { (gens[mod] != g || (mod && API.mod_off?(mod))) ? nil : blk.call }
        return true
      end

      # set(kind, id, text): kinds :item_name :item_description :item_plural :map_name :type_name
      def self.set(kind, id, text)
        mod = Registries.key(caller_locations(1, 40))
        return Registries.bad(mod, "Text.set kind #{kind.inspect} is not one of #{Registries::TEXT_KINDS.keys.inspect}") unless Registries::TEXT_KINDS.key?(kind)
        Registries.text[[kind, id]] = { :mod => mod, :text => text.to_s }
        Registries.apply_text if Registries.data_ready?
        return true
      end
    end

    module Sprites
      # decorate(:character, id = nil) { |sprite, character| } runs after every map sprite update
      def self.decorate(kind, id = nil, &blk)
        raise ArgumentError, "only :character sprites for now" unless kind == :character
        return API.on(:sprite_update, id, mod: Registries.key(caller_locations(1, 40))) { |ctx| blk.call(ctx[:sprite], ctx[:character]) }
      end

      def self.on_dispose(id = nil, &blk)
        return API.on(:sprite_dispose, id, mod: Registries.key(caller_locations(1, 40))) { |ctx| blk.call(ctx[:sprite], ctx[:character]) }
      end
    end

    module Theme
      NAMES = [:bg, :panel, :line, :txt, :dim, :sel, :acc, :up, :down, :warn].freeze unless const_defined?(:NAMES)

      # KIF's palette (KIF::PixelUI): :bg :panel :line :txt :dim :sel :acc :up :down :warn
      def self.color(name)
        n = name.to_s.downcase.to_sym
        return KIF::PixelUI.const_get(n.to_s.upcase) if NAMES.include?(n) && defined?(KIF::PixelUI)
        return Registries.instance_variable_get(:@colors)[n.to_s]
      end

      # a colour of your own: returns a Color and remembers it under `name`
      def self.register_color(name, rgb)
        mod = Registries.key(caller_locations(1, 40))
        return Registries.bad(mod, "Theme.register_color needs [r, g, b] (0..255)") unless rgb.is_a?(Array) && rgb.length == 3 && rgb.all? { |c| c.is_a?(Integer) && c.between?(0, 255) }
        return Registries.instance_variable_get(:@colors)[name.to_s.downcase] = Color.new(*rgb)
      end
    end

    module Fonts
      # Fonts the game can use (mkxp-z reads Fonts/ once at start: a font can not be added while running)
      def self.available
        dir = File.join(".", "Fonts")
        return [] unless File.directory?(dir)
        return Dir.children(dir).select { |f| f =~ /\.(ttf|otf)\z/i }.map { |f| File.basename(f, ".*") }.sort
      end
    end
  end
end
