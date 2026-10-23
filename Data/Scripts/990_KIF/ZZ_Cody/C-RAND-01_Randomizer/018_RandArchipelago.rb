#===============================================================================
# C-RAND-01 – Randomizer with Archipelago (C-AP-01) (2026-10-23)
#   Archipelago's logic is built on the normal doors and places the items at
#   its checks itself, so for a save linked to Archipelago:
#     * Entrances are off (a stored door layout is kept but not used);
#     * found / given items and TMs are never randomized (checks already give
#       Archipelago's item first; this also keeps the story items the logic
#       counts on at the other spots);
#     * NPCs asking for a Pokémon accept any Pokémon when Pokémon are
#       randomized (the logic doesn't know which Pokémon you can catch).
#   Everything else in the randomizer works as usual. The fixed values are
#   KIF::AP::FORCED; linking also writes them into the settings.
#   (This file loads after the randomizer; C-AP-01 loads before it.)
#===============================================================================
module KIF
  module Rand
    class << self
      alias kif_ap_dget dget unless method_defined?(:kif_ap_dget)
      alias kif_ap_item_part_on? item_part_on? unless method_defined?(:kif_ap_item_part_on?)

      def dget(key)
        v = KIF::AP.forced(key)
        return v.nil? ? kif_ap_dget(key) : v
      end

      def item_part_on?(it, ctx)
        return false if KIF::AP.on?
        return kif_ap_item_part_on?(it, ctx)
      end
    end

    module ER
      class << self
        alias kif_ap_active? active? unless method_defined?(:kif_ap_active?)

        def active?
          return false if KIF::AP.on?
          return kif_ap_active?
        end
      end
    end
  end
end
