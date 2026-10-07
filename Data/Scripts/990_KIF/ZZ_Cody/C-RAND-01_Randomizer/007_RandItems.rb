#===============================================================================
# C-RAND-01 – Randomizer, chunk 5: items (Cody, 2026-10-06)
#   * Item mode: Mapped (each item always becomes the same other item) or
#     Dynamic (every item ball, gift and shop slot rolls its own item; fixed
#     by the seed and the spot, so reloading gives the same item). TMs too.
#   * Found items / Found TMs / Given items / Given TMs / Shop items each only
#     affect their own part (PIF let Given TMs also change found TMs, ...).
#   * Trainer held items: Off / Random (each battle) / Fixed (per trainer).
#   * Keep categories: balls stay balls, medicine stays medicine, berries,
#     battle items, mail, evolution items, gems, held items, TMs, other.
#   * Keep shop basics: Poké Balls and Splicers stay buyable.
#   * Banned items: never a result. Starts with the items that have no use in
#     PIF (shards, apricorns, contest scarves, mail, ...) – Cody.
#===============================================================================
module KIF
  module Rand
    ITEM_SETTINGS = [
      [:item_mode, :enum, 2],        # Mapped / Dynamic
      [:keep_categories, :enum, 2],
      [:shop_basics, :enum, 2]
    ]
    # (only once, even if this file is loaded again)
    ITEM_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_KEYS.include?(st[0]) }
    ITEM_SETTINGS.each { |st| DATA_KEYS << st[0] unless DATA_KEYS.include?(st[0]) }
    DATA_DEFAULTS[:shop_basics] = 1

    # Items with no use in PIF (nothing to do with them but sell for little)
    JUNK_ITEMS = [:REDSHARD, :YELLOWSHARD, :BLUESHARD, :GREENSHARD,
                  :REDAPRICORN, :YELLOWAPRICORN, :BLUEAPRICORN, :GREENAPRICORN,
                  :PINKAPRICORN, :WHITEAPRICORN, :BLACKAPRICORN,
                  :SHOALSALT, :SHOALSHELL,
                  :REDSCARF, :BLUESCARF, :PINKSCARF, :GREENSCARF, :YELLOWSCARF,
                  :GRASSMAIL, :FLAMEMAIL, :BUBBLEMAIL, :BLOOMMAIL, :TUNNELMAIL, :STEELMAIL,
                  :HEARTMAIL, :SNOWMAIL, :SPACEMAIL, :AIRMAIL, :MOSAICMAIL, :BRICKMAIL,
                  :RAZZBERRY, :BLUKBERRY, :NANABBERRY, :WEPEARBERRY, :PINAPBERRY, :CORNNBERRY,
                  :MAGOSTBERRY, :RABUTABERRY, :NOMELBERRY, :SPELONBERRY, :PAMTREBERRY,
                  :WATMELBERRY, :DURINBERRY, :BELUEBERRY,
                  :RESETURGE, :ABILITYURGE, :ITEMURGE, :ITEMDROP, :UNKNOWN]

    SHOP_BASICS = [:DNASPLICERS, :SUPERSPLICERS, :INFINITESPLICERS, :INFINITESPLICERS2]

    def self.default_item_bans
      return JUNK_ITEMS.select { |i| GameData::Item.exists?(i) }
    end

    def self.item_bans
      data[:ban_items] = default_item_bans if data[:ban_items].nil?
      return data[:ban_items]
    end

    def self.dynamic_items?
      return dget(:item_mode) == 1
    end

    #---------------------------------------------------------------------------
    # Pools
    #---------------------------------------------------------------------------
    def self.tm_ok?(it)
      return it.is_TM? && !NON_RANDOMIZE_ITEMS.include?(it.id)
    end

    def self.item_randomizable?(it)
      return tm_ok?(it) if it.is_machine?
      return itemCanBeRandomized(it)
    end

    def self.all_items
      @all_items ||= GameData::Item.list_all.values.uniq { |i| i.id }.sort_by(&:id_number)
    end

    def self.item_category(it)
      return :tm if it.is_TM?
      return :ball if it.is_poke_ball?
      return :berry if it.is_berry?
      return :mail if it.is_mail?
      return :evolution if it.is_evolution_stone?
      return :gem if it.is_gem?
      return :medicine if it.pocket == 2
      return :battle if it.pocket == 7
      return :held if HELD_ITEMS.include?(it.id) || it.real_description.to_s =~ /\bheld\b/i
      return :other
    end

    # Sources: every item that can change. Targets: the same minus bans.
    def self.item_sources(tms)
      @sources_memo ||= {}
      return @sources_memo[tms] ||= all_items.select { |i| tms ? tm_ok?(i) : (!i.is_machine? && itemCanBeRandomized(i)) }
    end

    def self.item_targets(tms, category = nil)
      bans = item_bans
      key = [tms, category, dget(:keep_categories), bans.hash]
      @targets_memo ||= {}
      @targets_memo.clear if @targets_memo.length > 64
      return @targets_memo[key] ||= item_targets_uncached(tms, category, bans)
    end

    def self.item_targets_uncached(tms, category, bans)
      list = item_sources(tms).reject { |i| bans.include?(i.id) }
      if category && dget(:keep_categories) == 1
        same = list.select { |i| item_category(i) == category }
        list = same unless same.empty?
      end
      return list.map(&:id)
    end

    #---------------------------------------------------------------------------
    # Mapped: one map per seed (PIF's hashes, so its code keeps working)
    #---------------------------------------------------------------------------
    def self.build_item_map(tms)
      map = {}
      groups = item_sources(tms).group_by { |i| dget(:keep_categories) == 1 ? item_category(i) : :all }
      groups.keys.sort_by(&:to_s).each do |cat|
        targets = item_targets(tms, cat == :all ? nil : cat)
        next if targets.empty?
        bag = []
        groups[cat].each do |src|
          bag = targets.shuffle if bag.empty?
          map[src.id] = bag.pop
        end
      end
      return map
    end

    def self.shuffle_items
      $PokemonGlobal.randomItemsHash = build_item_map(false)
    end

    def self.shuffle_tms
      $PokemonGlobal.randomTMsHash = build_item_map(true)
    end

    def self.mapped_item(it)
      hash = it.is_TM? ? $PokemonGlobal.randomTMsHash : $PokemonGlobal.randomItemsHash
      if hash.nil?
        it.is_TM? ? pbShuffleTMs : pbShuffleItems
        hash = it.is_TM? ? $PokemonGlobal.randomTMsHash : $PokemonGlobal.randomItemsHash
      end
      return (hash && hash[it.id]) || it.id
    end

    #---------------------------------------------------------------------------
    # Dynamic: rolled from the seed and the spot, so it never changes
    #---------------------------------------------------------------------------
    def self.roll_item(it, *spot)
      targets = item_targets(it.is_TM?, item_category(it))
      return it.id if targets.empty?
      rng = Random.new(sub_seed(:item, *spot, it.id))
      return targets[rng.rand(targets.length)]
    end

    def self.event_id
      return (pbMapInterpreter.instance_variable_get(:@event_id) rescue 0).to_i
    end

    def self.map_id
      return $game_map ? $game_map.map_id : 0
    end

    # Which part an item belongs to (found / given), set by pbItemBall and
    # pbReceiveItem
    @item_ctx = nil
    class << self
      attr_accessor :item_ctx
    end

    def self.item_part_on?(it, ctx)
      if it.is_TM?
        return sw(SWITCH_RANDOM_GIVEN_TMS) if ctx == :given
        return sw(SWITCH_RANDOM_FOUND_TMS)
      end
      return sw(SWITCH_RANDOM_GIVEN_ITEMS) if ctx == :given
      return sw(SWITCH_RANDOM_FOUND_ITEMS)
    end

    def self.random_item_for(it, ctx)
      return it unless sw(SWITCH_RANDOM_ITEMS_GENERAL) && item_part_on?(it, ctx)
      return it unless item_randomizable?(it)
      new = dynamic_items? ? roll_item(it, ctx, map_id, event_id) : mapped_item(it)
      return GameData::Item.get(new)
    end

    #---------------------------------------------------------------------------
    # Shops
    #---------------------------------------------------------------------------
    def self.shop_basic?(it)
      return it.is_poke_ball? || SHOP_BASICS.include?(it.id)
    end

    def self.shop_item(item, slot)
      it = (GameData::Item.get(item) rescue nil)
      return item unless it
      return item if dget(:shop_basics) == 1 && shop_basic?(it)
      return item if it.is_machine? || !itemCanBeRandomized(it)
      new = dynamic_items? ? roll_item(it, :shop, map_id, event_id, slot) : mapped_item(it)
      ni = (GameData::Item.get(new) rescue nil)
      return item unless ni && ni.price > 0 && !Settings::EXCLUDE_FROM_RANDOM_SHOPS.include?(ni.id)
      return ni.id
    end

    #---------------------------------------------------------------------------
    # Trainer held items: Random = PIF (every battle), Fixed = per trainer
    #---------------------------------------------------------------------------
    @held_ctx = nil
    class << self
      attr_accessor :held_ctx
    end

    def self.held_pool
      bans = item_bans
      return HELD_ITEMS.select { |i| GameData::Item.exists?(i) && !bans.include?(i) }
    end

    # Fixed held item for a trainer's n-th Pokémon (also used by the log)
    def self.fixed_held(id, n, pool = held_pool)
      return nil if pool.empty?
      rng = Random.new(sub_seed(:held, id, n))
      return pool[rng.rand(pool.length)]
    end

    def self.random_held_item
      pool = held_pool
      return nil if pool.empty?
      if get(:held_items) == 2 && @held_ctx
        id, n = @held_ctx
        @held_ctx = [id, n + 1]
        return GameData::Item.get(fixed_held(id, n, pool))
      end
      return GameData::Item.get(pool.sample)
    end

    #---------------------------------------------------------------------------
    # Spoiler log for Dynamic: every item ball / gift in the maps' events
    #---------------------------------------------------------------------------
    ITEM_CALL = /pb(ItemBall|ReceiveItem)\(\s*(?::|PBItems::)(\w+)/

    # Every item ball / gift in the maps' events: [map id, map name, event id,
    # :found/:given, item id]. Map files never change while the game runs,
    # so they're read once (the log is written after every shuffle).
    @item_spots = nil
    def self.item_spots
      return @item_spots if @item_spots
      spots = []
      infos = (load_data("Data/MapInfos.rxdata") rescue {})
      infos.keys.sort.each do |mid|
        map = (load_data(sprintf("Data/Map%03d.rxdata", mid)) rescue nil)
        next unless map && map.events
        name = (pbGetMapNameFromId(mid) rescue mid.to_s)
        map.events.keys.sort.each do |eid|
          ev = map.events[eid]
          seen = {}
          ev.pages.each do |page|
            page.list.each do |cmd|
              text = case cmd.code
                     when 355, 655 then cmd.parameters[0].to_s
                     when 111 then cmd.parameters[0] == 12 ? cmd.parameters[1].to_s : ""
                     else ""
                     end
              text.scan(ITEM_CALL) do |kind, item|
                next if seen[[kind, item]]
                seen[[kind, item]] = true
                it = (GameData::Item.get(item.to_sym) rescue nil)
                next unless it
                spots << [mid, name, eid, (kind == "ItemBall") ? :found : :given, it.id]
              end
            end
          end
        end
      end
      @item_spots = spots
      return spots
    end

    def self.dynamic_item_lines
      lines = []
      item_spots.each do |mid, name, eid, ctx, item|
        it = GameData::Item.get(item)
        next unless item_part_on?(it, ctx) && item_randomizable?(it)
        new = roll_item(it, ctx, mid, eid)
        lines << "#{name} (#{ctx}): #{it.name} -> #{(GameData::Item.get(new).name rescue new)}"
      end
      return lines
    rescue => e
      return ["(item spots unavailable: #{e.message})"]
    end
  end
end

#-------------------------------------------------------------------------------
# Hooks
#-------------------------------------------------------------------------------
class Object
  alias kif_rand_pbItemBall pbItemBall unless method_defined?(:kif_rand_pbItemBall) || private_method_defined?(:kif_rand_pbItemBall)
  alias kif_rand_pbReceiveItem pbReceiveItem unless method_defined?(:kif_rand_pbReceiveItem) || private_method_defined?(:kif_rand_pbReceiveItem)
  alias kif_rand_pbGetRandomHeldItem pbGetRandomHeldItem unless method_defined?(:kif_rand_pbGetRandomHeldItem) || private_method_defined?(:kif_rand_pbGetRandomHeldItem)

  def pbItemBall(*args)
    old = KIF::Rand.item_ctx
    KIF::Rand.item_ctx = :found
    begin
      return kif_rand_pbItemBall(*args)
    ensure
      KIF::Rand.item_ctx = old
    end
  end

  def pbReceiveItem(*args)
    old = KIF::Rand.item_ctx
    KIF::Rand.item_ctx = :given
    begin
      return kif_rand_pbReceiveItem(*args)
    ensure
      KIF::Rand.item_ctx = old
    end
  end

  def pbGetRandomItem(item_id)
    return nil if item_id.nil?
    item = GameData::Item.get(item_id)
    return KIF::Rand.random_item_for(item, KIF::Rand.item_ctx || :found)
  end

  def replaceShopStockWithRandomized(stock)
    ret = []
    stock.each_with_index { |item, i| ret << KIF::Rand.shop_item(item, i) }
    return ret.uniq
  end

  def pbGetRandomHeldItem
    return KIF::Rand.random_held_item || kif_rand_pbGetRandomHeldItem
  end
end

module GameData
  class Trainer
    alias kif_rand_items_to_trainer to_trainer unless method_defined?(:kif_rand_items_to_trainer)

    def to_trainer
      KIF::Rand.held_ctx = [self.id, 0]
      begin
        return kif_rand_items_to_trainer
      ensure
        KIF::Rand.held_ctx = nil
      end
    end
  end
end
