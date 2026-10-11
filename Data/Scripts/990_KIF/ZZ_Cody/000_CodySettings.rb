#===============================================================================
# Cody Settings (loads before the Cody features in this folder)
# Cody's own additions to KIF Beta (not from KIF 0.20.7) get their own
# settings screen: Options → "Cody Settings", right below "KIF Settings".
# Same menus as KIF Settings (GLOBAL / PER-SAVE FILE sections), own colour.
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

class CodyOptionsScene < KifOptionsScene
  def kif_title; "Cody Settings"; end
  def kif_colors; [[230, 140, 40], [120, 70, 20]]; end

  def getDefaultDescription
    return _INTL("Cody's additions to KIF Beta")
  end

  def kif_menu_ids; KIF::Cody::MENUS.keys; end

  def pbGetOptions(inloadscreen = false)
    return kif_menu_buttons
  end
end

# Since Modules (2026-10-10) Cody's settings are listed under their module in
# Options > Modules; the "Cody Settings" button is no longer added.
class PokemonGameOption_Scene < PokemonOption_Scene

  def cody_open_settings
    pbFadeOutIn {
      scene = CodyOptionsScene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
    }
  end
end
