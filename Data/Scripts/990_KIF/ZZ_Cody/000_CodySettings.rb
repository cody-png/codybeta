#===============================================================================
# Cody Settings (loads before the Cody features in this folder)
# Menus for the additions that aren't from KIF 0.20.7. Their settings show
# in the settings screen under their module like every other setting.
#
# Features register with KIF::Options.add(<cody menu>, scope) { Option }.
# A category only shows once a feature uses it.
#===============================================================================
module KIF
  module Cody
    # id => [title, button description, base colour, shadow colour, button label]
    MENUS = {
      :cody_battles   => ["Cody: Battles",           "Battle additions",            [230, 140, 40], [120, 70, 20], "Battles"],
      :cody_breeding  => ["Cody: Breeding & Fusion", "Breeding and fusion additions", [220, 90, 150], [115, 45, 80], "Breeding & Fusion"],
      :cody_interface => ["Cody: Interface",         "Menu and screen additions",     [90, 170, 220], [45, 90, 115], "Interface"]
    }
    MENUS.each { |id, m| KIF::Options.register_menu(id, *m) }
  end
end
