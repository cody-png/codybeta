#===============================================================================
# KIF pause-menu injection
#
# PIF 6.8.2 builds the pause menu inside one long method
# (PokemonPauseMenu#pbStartPokemonMenu, 016_UI/001_UI_PauseMenu.rb:109), so KIF
# entries are injected into the list given to the scene's pbShowCommands
# instead of editing that method. If the player picks a KIF entry, its handler
# runs here and the menu is shown again; base entries are returned to the base
# loop with their original index.
#
#   KIF::PauseMenu.add(:kif_pc, _INTL("PC"),
#                      condition: proc { $PokemonSystem.kurayqol == 1 },
#                      handler:   proc { |scene| ...; :stay })
#
# A handler returns :stay (show the menu again) or :close (close the menu,
# same as KIF's `break` after "Can't use that here.").
# Entries are inserted right after "Bag" (KIF's position), in registration
# order.
#===============================================================================
module KIF
  module PauseMenu
    Entry = Struct.new(:id, :label, :condition, :handler, :icon, :order)
    @entries = []

    # order: position among KIF entries (KIF: PC 10, Heal 20, Kuray Shop 30,
    # Tutor.net 40); equal orders keep registration order.
    def self.add(id, label, condition: nil, handler:, icon: nil, order: 100)
      @entries.reject! { |e| e.id == id }
      @entries << Entry.new(id, label, condition, handler, icon, order)
    end

    def self.active_entries
      list = @entries.select { |e| (!defined?(KIF::Modules) || KIF::Modules.proc_active?(e.handler)) && (e.condition.nil? || e.condition.call) }
      return list.each_with_index.sort_by { |e, i| [e.order || 100, i] }.map(&:first)
    end

    def self.label_for(entry)
      text = entry.label.is_a?(Proc) ? entry.label.call : entry.label
      icon = entry.icon || "menuIcons/OPTIONS"
      return "  <icon=#{icon}>  " + _INTL(text)
    end

    # Index after which KIF entries are inserted (after "Bag", else after
    # "Pokémon", else at the top).
    def self.insert_position(commands)
      bag = commands.index { |c| c.to_s.include?(_INTL("Bag")) }
      return bag + 1 if bag
      pkmn = commands.index { |c| c.to_s.include?(_INTL("Pokémon")) }
      return pkmn + 1 if pkmn
      return 0
    end

    # Maps whose PC/Heal use KIF blocks (KIF 016_UI/001_UI_PauseMenu.rb).
    # Same IDs and names in PIF 6.8.2 (checked against MapInfos.rxdata).
    RESTRICTED_MAPS = [
      315, 316, 317, 318, 328, 343,                 # Elite Four / Champion / Gate
      776, 777, 778, 779, 780, 781, 782, 783, 784,  # Mt. Silver
      722, 723, 724, 720,                           # Dream sequence
      304, 306, 307                                 # Victory Road
    ]
    SHOP_RESTRICTED_MAPS = [315, 316, 317, 318, 328, 341]

    def self.restricted?(list = RESTRICTED_MAPS)
      return false unless Settings::KANTO
      return false if KIF.marker?("DemICE.krs")
      return list.include?($game_map.map_id)
    end
  end
end

# A prepended module, not an alias: mods that hook pbShowCommands themselves
# (alias + def; Kanto Reloaded's PokeVial looks for KIF's "Heal Pokémon" row
# to replace it) then run inside this one and see KIF's rows, as they did in
# KIF 0.20.7 where those rows were part of the command list. (An alias would
# have put KIF inside the mod's hook: PokeVial never saw the Heal row.)
module KIF
  module PauseMenu
    module SceneHook
      def pbShowCommands(commands)
        KIF::PauseMenu.show_commands(self, commands) { |list| super(list) }
      end
    end

    def self.show_commands(scene, commands)
      entries = active_entries
      return yield(commands) if entries.empty?
      pos = insert_position(commands)
      shown = commands.dup
      shown.insert(pos, *entries.map { |e| label_for(e) })
      loop do
        ret = yield(shown)
        return ret if ret < 0 || ret < pos
        return ret - entries.length if ret >= pos + entries.length
        entry = entries[ret - pos]
        result = entry.handler.call(scene)
        return -1 if result == :close
        scene.pbShowMenu
      end
    end
  end
end

PokemonPauseMenu_Scene.prepend(KIF::PauseMenu::SceneHook)

class Game_Temp
  attr_accessor :fromkurayshop   # KIF: storage/mart opened from the pause menu
end
