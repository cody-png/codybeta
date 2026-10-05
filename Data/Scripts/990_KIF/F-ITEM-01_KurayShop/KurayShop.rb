#===============================================================================
# F-ITEM-01 – Kuray Shop + Streamer's Dream
# Source: KIF 0.20.7
#   016_UI/001_UI_PauseMenu.rb:138, :263-448  pause entry, stock and prices
#   016_UI/020_UI_PokeMart.rb:59-60, :283-300, :456-483  free items, KIF
#     background, no map scroll when opened from the menu
#   016_UI/015_UI_Options.rb:2798-2816  "Streamer's Dream" (Others, default Off)
#   Graphics/Pictures/martScreenKuray.png
#
# Pause menu "Kuray Shop" (with Kuray QoL On, not in the Bug Contest, not in
# the Elite Four / Champion rooms). Sells TMs, PP items, Power items, battle
# items, Transgender Stone, Mist Stone (P999,999 before the 8th badge),
# Devolution Spray, Rare Candy, Master Ball, Max Repel, Rage Candy Bar,
# Eviolite, Deep Sea Scale, and Rocket Balls when Rocket Mode is on.
# Streamer's Dream: Rare Candy, Master Ball, Max Repel, Rage Candy Bar,
# Transgender Stone, Mist Stone and Devolution Spray are free (also makes the
# PC shiny gamble free).
#
# 6.8.2 adaptations:
#   * KIF wrote prices into $game_temp.mart_prices by item number and used -1
#     for "free". In 6.8.2 -1 already means "no override" and item numbers
#     changed, so the shop's prices are looked up by item symbol in
#     PokemonMartAdapter#getPrice while the shop is open; mart_prices is not
#     touched.
#   * KIF's TMs are listed by the move they teach (TM numbers differ between
#     versions), resolved when the shop opens; items missing from 6.8.2 are
#     skipped.
#   * K-Eggs (KIF items 2000-2032) and their unlock messages come with F-ITEM-02.
#   * Port addition (Cody, 2026-10-05): the Celadon Prize Corner TMs Hyper
#     Beam, Flamethrower, Ice Beam and Thunderbolt at P15,000 each.
#   * KIF's "Dream more!" (unlimited Wonder Trades) was commented out in KIF.
#===============================================================================
KIF::Options.define(:kuraystreamerdream, 0, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Streamer's Dream"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kuraystreamerdream },
                 proc { |value| $PokemonSystem.kuraystreamerdream = value },
                 [_INTL("No Rare Candies/Master Balls/etc free in Kuray Shop"),
                  _INTL("Rare Candies/Master Balls and more are free in Kuray Shop")])
}

module KIF
  module KurayShop
    # [item or [:TM, move], buy, sell, free with Streamer's Dream?]
    ITEMS = [
      [:TRANSGENDERSTONE, 6900, 3450, true],
      [:DEVOLUTIONSPRAY, 8200, 4100, true],
      [:MISTSTONE, :mist, 24000, true],
      [:ETHER, 1200, 600], [:ELIXIR, 4000, 2000], [:PPUP, 9100, 4550],
      [:MAXETHER, 3600, 1800], [:MAXELIXIR, 12000, 6000], [:PPMAX, 29120, 14560],
      [:POWERWEIGHT, 3000, 1500], [:POWERBRACER, 3000, 1500], [:POWERBELT, 3000, 1500],
      [:POWERLENS, 3000, 1500], [:POWERBAND, 3000, 1500], [:POWERANKLET, 3000, 1500],
      [[:TM, :LIGHTSCREEN], 10000, 5000], [[:TM, :RETURN], 10000, 5000],
      [[:TM, :FACADE], 10000, 5000], [[:TM, :ROUND], 10000, 5000],
      [[:TM, :FLING], 10000, 5000], [[:TM, :SKYDROP], 10000, 5000],
      [[:TM, :INCINERATE], 10000, 5000], [[:TM, :ROCKPOLISH], 10000, 5000],
      [[:TM, :STONEEDGE], 10000, 5000], [[:TM, :ROCKTHROW], 10000, 5000],
      [[:TM, :SPORE], 30000, 15000], [[:TM, :TOXICSPIKES], 30000, 15000],
      [[:TM, :BRUTALSWING], 30000, 15000], [[:TM, :AURORAVEIL], 30000, 15000],
      [[:TM, :DAZZLINGGLEAM], 30000, 15000], [[:TM, :FOCUSPUNCH], 30000, 15000],
      [[:TM, :INFESTATION], 30000, 15000], [[:TM, :LEECHLIFE], 30000, 15000],
      [[:TM, :POWERUPPUNCH], 30000, 15000], [[:TM, :SHOCKWAVE], 30000, 15000],
      [[:TM, :SMARTSTRIKE], 30000, 15000], [[:TM, :STEELWING], 30000, 15000],
      [[:TM, :STOMPINGTANTRUM], 30000, 15000], [[:TM, :THROATCHOP], 30000, 15000],
      [[:TM, :SCALD], nil, nil],          # KIF listed it at its normal price
      # Celadon Prize Corner TMs (Cody, 2026-10-05; still in the Prize Corner too)
      [[:TM, :HYPERBEAM], 15000, 7500], [[:TM, :FLAMETHROWER], 15000, 7500],
      [[:TM, :ICEBEAM], 15000, 7500], [[:TM, :THUNDERBOLT], 15000, 7500],
      [:FOCUSSASH, 6000, 3000], [:FLAMEORB, 6000, 3000], [:TOXICORB, 6000, 3000],
      [:LIFEORB, 6000, 3000],
      [:DEEPSEASCALE, 10000, 1000],
      [:RAGECANDYBAR, 10000, 0, true], [:RARECANDY, 10000, 0, true],
      [:MASTERBALL, 960000, 0, true], [:MAXREPEL, 700, 350, true],
      [:EVIOLITE, 4000, 2000]
    ]
    ROCKET_BALL = [:ROCKETBALL, 1000, 500]

    @open = false
    @prices = {}
    class << self
      attr_reader :prices
      def open?; @open; end
    end

    def self.free?
      return $PokemonSystem && $PokemonSystem.kuraystreamerdream.to_i != 0
    end

    def self.tm_for(move)
      @tm_cache ||= {}
      return @tm_cache[move] if @tm_cache.has_key?(move)
      found = nil
      GameData::Item.each do |item|
        next unless item.is_TM? && item.move == move
        found = item.id
        break
      end
      @tm_cache[move] = found
      return found
    end

    def self.resolve(entry)
      return tm_for(entry[1]) if entry.is_a?(Array)
      return GameData::Item.exists?(entry) ? entry : nil
    end

    def self.badge8?
      return $game_switches[SWITCH_GOT_BADGE_8] if defined?(SWITCH_GOT_BADGE_8)
      return $Trainer && $Trainer.badge_count >= 8
    end

    # Builds the stock and the price table; returns the stock list.
    def self.prepare
      @prices = {}
      stock = []
      list = ITEMS.dup
      list << ROCKET_BALL if $PokemonSystem.respond_to?(:rocketballsteal) && $PokemonSystem.rocketballsteal.to_i > 0
      list.each do |entry, buy, sell, dream|
        id = resolve(entry)
        next unless id
        stock << id unless stock.include?(id)
        if dream && free?
          @prices[id] = [0, 0]
        elsif buy == :mist
          @prices[id] = [badge8? ? 42000 : 999999, sell]
        elsif buy
          @prices[id] = [buy, sell]
        end
      end
      return sort_tms(stock)
    end

    # TMs are listed in TM-number order inside their block (Cody, 2026-10-05)
    def self.sort_tms(stock)
      tm = proc { |id| (GameData::Item.get(id).is_TM? rescue false) }
      idx = stock.each_index.select { |i| tm.call(stock[i]) }
      sorted = idx.map { |i| stock[i] }.sort_by do |id|
        num = (GameData::Item.get(id).name[/\d+/] rescue nil)
        [num ? num.to_i : 9999, id.to_s]
      end
      idx.each_with_index { |i, k| stock[i] = sorted[k] }
      return stock
    end

    def self.open
      stock = prepare
      @open = true
      $game_temp.fromkurayshop = 1
      begin
        pbFadeOutIn {
          scene = PokemonMart_Scene.new
          screen = PokemonMartScreen.new(scene, stock)
          screen.pbBuyScreen
        }
      ensure
        @open = false
        @prices = {}
        $game_temp.fromkurayshop = nil
      end
    end
  end
end

class PokemonMartAdapter
  alias kif_shop_getPrice getPrice unless method_defined?(:kif_shop_getPrice)

  def getPrice(item, selling = false)
    if KIF::KurayShop.open? && (p = KIF::KurayShop.prices[item])
      return selling ? p[1] : p[0]
    end
    return kif_shop_getPrice(item, selling)
  end
end

class PokemonMart_Scene
  alias kif_shop_scroll_map scroll_map unless method_defined?(:kif_shop_scroll_map)
  alias kif_shop_scroll_back_map scroll_back_map unless method_defined?(:kif_shop_scroll_back_map)
  alias kif_shop_pbStartBuyOrSellScene pbStartBuyOrSellScene unless method_defined?(:kif_shop_pbStartBuyOrSellScene)

  # Opened from the pause menu: no map scroll (KIF).
  def scroll_map
    kif_shop_scroll_map unless KIF::KurayShop.open?
  end

  def scroll_back_map
    kif_shop_scroll_back_map unless KIF::KurayShop.open?
  end

  def pbStartBuyOrSellScene(*args)
    ret = kif_shop_pbStartBuyOrSellScene(*args)
    if KIF::KurayShop.open? && pbResolveBitmap("Graphics/Pictures/KIF/martScreenKuray")
      @sprites["background"].setBitmap("Graphics/Pictures/KIF/martScreenKuray")
    end
    return ret
  end
end

KIF::PauseMenu.add(:kif_shop, "Kuray Shop", icon: "menuIcons/BAG", order: 30,
  condition: proc { $PokemonSystem.kurayqol == 1 && !pbInBugContest? },
  handler: proc { |scene|
    if KIF::PauseMenu.restricted?(KIF::PauseMenu::SHOP_RESTRICTED_MAPS)
      scene.pbHideMenu
      pbMessage(_INTL("Can't use that here."))
      next :close
    end
    pbPlayDecisionSE
    KIF::KurayShop.open
    :stay
  })
