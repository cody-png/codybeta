#===============================================================================
# F-ITEM-02 – K-Eggs (Kuray Eggs, by Reïzod)
# Source: KIF 0.20.7
#   201_Kuray/001_KurayEggs.rb:5-15        tier tables
#   201_Kuray/001_KurayEggs.rb:539-683     the 33 items (kurayeggs_loadsystem)
#   201_Kuray/001_KurayEggs.rb:685-722     species pools
#   201_Kuray/001_KurayEggs.rb:794-962     using an egg (kurayeggs_triggereggitem)
#   201_Kuray/001_KurayEggs.rb:981-1191    egg -> pool, tier roll, weighted pick
#   016_UI/020_UI_PokeMart.rb:333-399      unlocks + rewards when the Kuray Shop opens
#   016_UI/001_UI_PauseMenu.rb:391-433     Kuray Shop stock and prices
#   016_UI/015_UI_Options.rb:2435-2462     options (Battles & Pokemons menu)
#   Graphics/Items/KURAYEGG_*.png -> Graphics/Pictures/KIF/Items/
#
# Bag items that give a level 1 Pokémon (or an Egg, "K-Eggs Usage") from a
# pool: any, a type, a BST tier (Starter / 1-8 Badges / Elite 4), legendary,
# forced fusion or forced non-fusion. 10x the Wild Shiny Odds (Sparkling
# 40x). Picks are weighted by catch rate unless "K-Eggs Rarity" is Off. Tier
# eggs land one tier lower or higher 10% of the time each.
# The Kuray Shop sells them; Starter/badge/Elite 4 eggs unlock with progress,
# announced when the shop opens, each unlock giving "K-Eggs Rewards" eggs.
#
# 6.8.2 adaptations:
#   * Items keep KIF's symbols and numbers (2000-2032; 6.8.2 ends at 705) so
#     eggs in old KIF saves become real items again (F-CORE-02).
#   * Names/descriptions are kept on the items themselves (6.8.2 has no
#     MessageTypes.set); icons come from Graphics/Pictures/KIF/Items.
#   * Pools cover 6.8.2's base species (1-NB_POKEMON, now 576).
#   * Port fix: with the PC boxes full the egg is not used up (KIF consumed
#     it and gave nothing).
#   * Port addition (Cody, 2026-10-05): "Hoenn K-Egg" (item 2033), only the
#     species 6.8.2 added after KIF (dex 502-576), as a test egg. Sold in the
#     Kuray Shop at P20,000; uses the Random K-Egg icon (no art of its own).
#===============================================================================
KIF::Options.define(:kurayeggs_fusionpool, 0, :save)
KIF::Options.define(:kurayeggs_rarity, 0, :save)
KIF::Options.define(:kurayeggs_fusionodds, 20, :save)
KIF::Options.define(:kurayeggs_instanthatch, 0, :save)
KIF::Options.define(:gymrewardeggs, 3, :save)
KIF::Options.define(:trainerprogress, [], :save)   # unlocked tiers ("0".."9")

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("K-Eggs Fusion Pool"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kurayeggs_fusionpool },
                 proc { |value| $PokemonSystem.kurayeggs_fusionpool = value },
                 [_INTL("In case of fusion, the other Pokemon is random."),
                  _INTL("In case of fusion, the other Pokemon must be from k-egg's pool as well.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("K-Eggs Rarity"), [_INTL("On"), _INTL("Off")],
                 proc { $PokemonSystem.kurayeggs_rarity },
                 proc { |value| $PokemonSystem.kurayeggs_rarity = value },
                 [_INTL("Pokemons' rarity in k-eggs depend of their catch rate."),
                  _INTL("All Pokemons have the same odds to come from the k-eggs.")])
}
KIF::Options.add(:battles, :save) {
  SliderOption.new(_INTL("K-Eggs Fusion Odds"), 0, 100, 1,
                   proc { $PokemonSystem.kurayeggs_fusionodds },
                   proc { |value| $PokemonSystem.kurayeggs_fusionodds = value },
                   _INTL("x% | Probability that a fusion hatches from Kuray Eggs (Default: 20%)"))
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("K-Eggs Usage"), [_INTL("Pokemon"), _INTL("Egg")],
                 proc { $PokemonSystem.kurayeggs_instanthatch },
                 proc { |value| $PokemonSystem.kurayeggs_instanthatch = value },
                 [_INTL("When Kuray Egg item used, spawns a Pokemon."),
                  _INTL("When Kuray Egg item used, spawns an Egg that contains a Pokemon.")])
}
KIF::Options.add(:battles, :save) {
  SliderOption.new(_INTL("K-Eggs Rewards"), 0, 10, 1,
                   proc { $PokemonSystem.gymrewardeggs },
                   proc { |value| $PokemonSystem.gymrewardeggs = value },
                   _INTL("Numbers of obtained K-Eggs upon unlocking each one through progression (Default: 3)"))
}

module KIF
  module KurayEggs
    FIRST_ID = 2000            # KIF Settings::KURAY_EGGS_ID
    MINBST     = [0, 280, 300, 380, 430, 450, 470, 480, 490, 500]
    MAXBST     = [288, 319, 400, 470, 480, 490, 505, 530, 555, 1000000]
    MINBSTSHOW = [180, 280, 300, 380, 430, 450, 470, 480, 490, 500]
    MAXBSTSHOW = [288, 319, 400, 470, 480, 490, 505, 530, 555, 754]
    TYPES = ["Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel",
             "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark", "Fairy"]
    BASE_PRICE = 5000
    TIER_PRICES = [500, 800, 1200, 2000, 3500, 5000, 7000, 10000, 12000, 15000]
    ICON_FOLDER = "Graphics/Pictures/KIF/Items/"
    HOENN_FIRST = 502          # first species after KIF's 501

    # [symbol, effect, name, price, description] in KIF's id order
    def self.definitions
      return @defs if @defs
      defs = []
      add = proc { |name, price, desc| defs << [:"KURAYEGG_#{name.upcase.gsub(' ', '_')}", defs.length, "#{name} K-Egg", price, desc] }
      add.call("Random", BASE_PRICE * 3, "Egg with ANY Pokémon. 10x shiny odds.")
      add.call("Sparkling", BASE_PRICE * 6, "Egg with ANY Pokémon. 40x shiny odds.")
      TYPES.each { |t| add.call(t, BASE_PRICE * 4, "Egg with #{t.upcase}-type Pokémon. 10x shiny odds.") }
      add.call("Fusion", BASE_PRICE * 4, "Egg with ANY Pokémon. 10x shiny odds. Fusion guaranteed.")
      add.call("Base", BASE_PRICE * 2, "Egg with ANY Pokémon. 10x shiny odds. Non-fused guaranteed.")
      10.times do |t|
        name = (t == 9) ? "Elite 4" : (t == 1) ? "1 Badge" : (t == 0) ? "Starter" : "#{t} Badges"
        add.call(name, TIER_PRICES[t],
                 "Egg with a Pokémon who's BST is between #{MINBSTSHOW[t]} and #{MAXBSTSHOW[t]}. 10x shiny odds.")
      end
      add.call("Legendary", BASE_PRICE * 5, "Egg with a LEGENDARY Pokémon. 10x shiny odds.")
      # Port addition (Cody): 6.8.2's new species only
      add.call("Hoenn", BASE_PRICE * 4, "Egg with a Pokémon new to PIF 6.8.2 (Dex 502-576). 10x shiny odds.")
      @defs = defs
      return defs
    end

    def self.symbol(effect); return definitions[effect][0]; end
    def self.egg?(item); return definitions.any? { |d| d[0] == item }; end

    # KIF kurayeggs_iteminject
    def self.register_items
      definitions.each do |sym, effect, name, price, desc|
        GameData::Item.register({
          :id => sym, :id_number => FIRST_ID + effect, :name => name, :name_plural => name + "s",
          :pocket => 1, :price => price, :description => desc,
          :field_use => 2, :battle_use => 0, :type => 0, :move => nil
        })
        item = GameData::Item.get(sym)
        item.instance_variable_set(:@kif_name, name)
        item.instance_variable_set(:@kif_name_plural, name + "s")
        item.instance_variable_set(:@kif_description, desc)
        ItemHandlers::UseInField.add(sym, proc { |it| next KIF::KurayEggs.use(effect, it) })
      end
      @pools = {}
    end

    #---------------------------------------------------------------------------
    # Pools: [[species, catch_rate], ...] (KIF :685-722, :1098-1120)
    #---------------------------------------------------------------------------
    def self.pool(key)
      @pools ||= {}
      return @pools[key] if @pools[key]
      list = []
      (1..NB_POKEMON).each do |i|
        sp = GameData::Species.get(i)
        ok = case key
             when "Random"    then true
             when "Legendary" then LEGENDARIES_LIST.include?(sp.id)
             when "Hoenn"     then i >= HOENN_FIRST
             when /^\d$/
               t = key.to_i
               bst = calcBaseStatsSum(sp.id)
               bst >= MINBST[t] && bst <= MAXBST[t]
             else
               type = key.upcase.to_sym
               sp.type1 == type || sp.type2 == type
             end
        list << [sp.id, sp.catch_rate] if ok
      end
      @pools[key] = list
      return list
    end

    # KIF kurayeggs_arraychooser
    def self.pick(list)
      return nil if list.nil? || list.empty?
      return list[rand(list.size)][0] if $PokemonSystem.kurayeggs_rarity.to_i == 1
      total = list.inject(0) { |sum, e| sum + e[1] }
      r = rand([total, 1].max)
      cur = 0
      list.each do |e|
        cur += e[1]
        return e[0] if r < cur
      end
      return list.last[0]
    end

    # KIF kurayeggs_choose + kurayeggs_effectfromid
    def self.choose(effect)
      case effect
      when 0, 1, 20, 21 then return pick(pool("Random"))
      when 2..19        then return pick(pool(TYPES[effect - 2]))
      when 32           then return pick(pool("Legendary"))
      when 33           then return pick(pool("Hoenn"))
      when 22..31
        tier = effect - 22
        roll = rand(1..100)
        if roll <= 10 && tier > 0
          tier -= 1
        elsif roll <= 20 && tier < 9
          tier += 1
        end
        return pick(pool(tier.to_s))
      end
      return nil
    end

    #---------------------------------------------------------------------------
    # Using an egg (KIF kurayeggs_triggereggitem :794-962)
    #---------------------------------------------------------------------------
    def self.use(effect, item)
      if pbBoxesFull?
        pbMessage(_INTL("There's no more room for Pokémon!"))   # port fix: egg kept
        return 0
      end
      item_name = GameData::Item.get(item).name
      pbUseItemMessage(item)
      pkmn = nil
      sparkling = (effect == 1)
      k_type = (2..19).include?(effect) ? TYPES[effect - 2].upcase.to_sym : nil
      20.times do
        mon = choose(effect)
        forced = (effect == 20) ? 2 : (effect == 21) ? 1 : 0
        odds = $PokemonSystem.kurayeggs_fusionodds.to_i
        forced = 2 if forced != 1 && odds > 0 && rand(1..100) <= odds
        if forced == 2
          mon2 = ($PokemonSystem.kurayeggs_fusionpool.to_i == 1) ? choose(effect) : pick(pool("Random"))
          head, body = (rand(1..100) <= 50) ? [mon2, mon] : [mon, mon2]
          pkmn = Pokemon.new(getFusedPokemonIdFromSymbols(body, head), 1)
        else
          pkmn = Pokemon.new(mon, 1)
        end
        break if k_type.nil? || pkmn.type1 == k_type || pkmn.type2 == k_type
      end
      if $PokemonSystem.kurayeggs_instanthatch.to_i == 1
        pkmn.name           = _INTL("Egg")
        pkmn.steps_to_hatch = pkmn.species_data.hatch_steps
        pkmn.hatched_map    = 0
        pkmn.obtain_method  = 1
      end
      odds = $PokemonSystem.shinyodds.to_i * 10
      odds *= 4 if sparkling
      pkmn.shiny = true if rand(65536) < odds
      pkmn.time_form_set = nil
      pkmn.form          = 0 if pkmn.isSpecies?(:SHAYMIN)
      pkmn.heal
      pkmn.obtain_text = item_name
      return 0 unless pbAddPokemon(pkmn, 1, true, true)
      if $Trainer.pokedex.respond_to?(:register_unfused_pkmn)
        $Trainer.pokedex.register_unfused_pkmn(pkmn).each do |unfused|
          pbMessage(_INTL("{1}'s data was added to the Pokédex", GameData::Species.get(unfused).name))
        end
      end
      return 3
    rescue => e
      KIF.log("K-Egg failed: #{e.class}: #{e.message}")
      return 0
    end

    #---------------------------------------------------------------------------
    # Kuray Shop stock and unlocks (KIF PauseMenu :391-433, PokeMart :333-399)
    #---------------------------------------------------------------------------
    def self.badge?(n)
      sw = Object.const_get("SWITCH_GOT_BADGE_#{n}") rescue nil
      return sw ? $game_switches[sw] : ($Trainer && $Trainer.badge_count >= n)
    end

    def self.elite4?
      return $game_variables[VAR_STAT_NB_ELITE_FOUR].to_i >= 1 if defined?(VAR_STAT_NB_ELITE_FOUR)
      return false
    end

    def self.shop_stock
      ids = [0, 1, 32, 33, 21, 20] + (2..19).to_a + [22]
      (1..8).each { |n| ids << 22 + n if badge?(n) }
      ids << 31 if elite4?
      return ids.map { |e| symbol(e) }
    end

    def self.give_reward(scene, effect)
      qty = $PokemonSystem.gymrewardeggs.to_i
      return if qty < 1
      sym = symbol(effect)
      $PokemonBag.pbStoreItem(sym, qty)
      name = GameData::Item.get(sym).name
      if qty > 1
        scene.pbDisplayPaused(_INTL("You received {2}x {1}s!", name, qty))
      else
        scene.pbDisplayPaused(_INTL("You received a {1}!", name))
      end
    end

    def self.unlock(scene)
      prog = $PokemonSystem.trainerprogress
      unless prog.include?("0")
        prog.push("0")
        scene.pbDisplayPaused(_INTL("You unlocked Starter K-Eggs!"))
        give_reward(scene, 22)
      end
      (1..8).each do |n|
        next if !badge?(n) || prog.include?(n.to_s)
        prog.push(n.to_s)
        if n == 1
          scene.pbDisplayPaused(_INTL("You unlocked 1 Badge K-Eggs!"))
        else
          scene.pbDisplayPaused(_INTL("You unlocked {1} Badges K-Eggs!", n))
        end
        give_reward(scene, 22 + n)
      end
      if elite4? && !prog.include?("9")
        prog.push("9")
        scene.pbDisplayPaused(_INTL("You unlocked Elite 4 K-Eggs!"))
        give_reward(scene, 31)
      end
    end
  end
end

KIF::DataLoad.after_load_all("K-Eggs items") { KIF::KurayEggs.register_items }

module GameData
  class Item
    alias kif_eggs_name name unless method_defined?(:kif_eggs_name)
    alias kif_eggs_name_plural name_plural unless method_defined?(:kif_eggs_name_plural)
    alias kif_eggs_description description unless method_defined?(:kif_eggs_description)

    def name;        return @kif_name || kif_eggs_name;                       end
    def name_plural; return @kif_name_plural || kif_eggs_name_plural;         end
    def description; return @kif_description || kif_eggs_description;         end

    class << self
      alias kif_eggs_icon_filename icon_filename unless method_defined?(:kif_eggs_icon_filename)

      def icon_filename(item)
        data = (try_get(item) rescue nil)
        if data && KIF::KurayEggs.egg?(data.id)
          path = KIF::KurayEggs::ICON_FOLDER + data.id.to_s
          return path if pbResolveBitmap(path)
          path = KIF::KurayEggs::ICON_FOLDER + "KURAYEGG_RANDOM"   # Hoenn K-Egg has no icon of its own
          return path if pbResolveBitmap(path)
        end
        return kif_eggs_icon_filename(item)
      end
    end
  end
end

# Kuray Shop: K-Eggs after KIF's other items (free with Streamer's Dream)
module KIF
  module KurayShop
    class << self
      alias kif_eggs_prepare prepare unless method_defined?(:kif_eggs_prepare)

      def prepare
        stock = kif_eggs_prepare
        KIF::KurayEggs.shop_stock.each do |sym|
          next unless GameData::Item.exists?(sym)
          stock << sym unless stock.include?(sym)
          price = GameData::Item.get(sym).price
          @prices[sym] = free? ? [0, 0] : [price, (price / 2.0).round]
        end
        return stock
      end
    end
  end
end

class PokemonMart_Scene
  alias kif_eggs_pbStartBuyOrSellScene pbStartBuyOrSellScene unless method_defined?(:kif_eggs_pbStartBuyOrSellScene)

  def pbStartBuyOrSellScene(*args)
    ret = kif_eggs_pbStartBuyOrSellScene(*args)
    begin
      KIF::KurayEggs.unlock(self) if KIF::KurayShop.open?
    rescue => e
      KIF.log("K-Eggs unlock failed: #{e.message}")
    end
    return ret
  end
end
