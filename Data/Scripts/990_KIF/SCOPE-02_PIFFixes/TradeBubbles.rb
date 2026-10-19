#===============================================================================
# SCOPE-02 – PIF fix: every in-game trade offer shows the trade bubble
# (2026-10-15)
# PIF shows the trade bubble over an NPC whose event page has a "tradeIcon"
# comment (052_InfiniteFusion/Gameplay/Quests/QuestIcons.rb). Only 18 of the
# 46 pages that offer a trade (pbStartTrade) have that comment; the others -
# the Cerulean man who trades his Yanma for a Paras, NPC traders on Route 2,
# Route 5, Vermilion, Fuchsia and in several Pokémon Centers, and trainers on
# Routes 3/7/9/11/13/25, Rock Tunnel and Viridian Forest who offer a trade
# after being beaten - showed none. A page that calls pbStartTrade now counts
# as tagged. Once the trade is done the event switches to another page, so
# the bubble goes away as it does for PIF's tagged traders.
#===============================================================================
module KIF
  module TradeBubbles
    # weak: every map load makes new page objects, so a plain Hash kept one
    # dead entry per page seen for the whole session
    @pages = ObjectSpace::WeakMap.new

    def self.trade_page?(page)
      return false unless page
      return @pages[page] if @pages.key?(page)
      found = (page.list || []).any? do |c|
        [355, 655, 111].include?(c.code) && c.parameters.any? { |p| p.is_a?(String) && p.include?("pbStartTrade") }
      end
      @pages[page] = found
      return found
    rescue StandardError
      return false
    end
  end
end

class Game_Event
  alias kif_tb_detectTradeIcon detectTradeIcon unless method_defined?(:kif_tb_detectTradeIcon)

  def detectTradeIcon(event)
    ret = kif_tb_detectTradeIcon(event)
    return ret if ret
    return nil unless validateEventIsCompatibleWithIcons(event)
    return KIF::TradeBubbles.trade_page?(pbGetActiveEventPage(event)) ? true : nil
  end
end
