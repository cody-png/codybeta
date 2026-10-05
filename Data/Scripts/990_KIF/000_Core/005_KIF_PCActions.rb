#===============================================================================
# KIF "Kuray Actions" PC submenu (F-PC-01 part)
# Source: KIF 0.20.7 016_UI/017_UI_PokemonStorage.rb:1818-1920 (pbKurayAct)
#         and :3383 (menu entry "Kuray Actions" after "Release")
#
# PIF 6.8.2 builds the Pokémon menu inside PokemonStorageScreen#
# organizeActions. While that method runs, the list it shows is recognised in
# pbShowCommands and "Kuray Actions" is inserted after "Release". Picking it
# opens the KIF submenu; the base method then sees "Cancel".
#
#   KIF::PCActions.add(:id, proc { |pkmn| label or nil },
#                      proc { |screen, pkmn, selected, heldpoke| ... })
# Actions appear in registration order; a nil label hides the action.
#===============================================================================
module KIF
  module PCActions
    Action = Struct.new(:id, :label, :handler)
    @actions = []

    def self.add(id, label, handler)
      @actions.reject! { |a| a.id == id }
      @actions << Action.new(id, label, handler)
    end

    def self.available(pkmn)
      return @actions.map { |a| [a, (a.label.call(pkmn) rescue nil)] }.select { |_, l| l }
    end

    # Money helper used by several actions (KIF "Streamer's Dream" makes
    # everything free; that option comes with the Kuray Shop).
    def self.price(base)
      return 0 if $PokemonSystem.respond_to?(:kuraystreamerdream) && $PokemonSystem.kuraystreamerdream.to_i != 0
      return base
    end
  end
end

class PokemonStorageScreen
  alias kif_pc_organizeActions organizeActions unless method_defined?(:kif_pc_organizeActions)

  def organizeActions(selected, pokemon, heldpoke, isTransferBox)
    @kif_organize = [selected, pokemon, heldpoke, isTransferBox]
    begin
      return kif_pc_organizeActions(selected, pokemon, heldpoke, isTransferBox)
    ensure
      @kif_organize = nil
    end
  end

  alias kif_pc_pbShowCommands pbShowCommands unless method_defined?(:kif_pc_pbShowCommands)

  def pbShowCommands(msg, commands, index = 0)
    ctx = @kif_organize
    return kif_pc_pbShowCommands(msg, commands, index) unless ctx
    @kif_organize = nil   # only the first (organize) menu
    selected, pokemon, heldpoke, isTransferBox = ctx
    pkmn = heldpoke || pokemon
    release_idx = commands.index(_INTL("Release"))
    cancel_idx = commands.index(_INTL("Cancel"))
    return kif_pc_pbShowCommands(msg, commands, index) if !pkmn || isTransferBox || !release_idx || !cancel_idx
    return kif_pc_pbShowCommands(msg, commands, index) if KIF::PCActions.available(pkmn).empty?
    shown = commands.dup
    pos = release_idx + 1
    shown.insert(pos, _INTL("Kuray Actions"))
    ret = kif_pc_pbShowCommands(msg, shown, index)
    if ret == pos
      kif_kuray_actions(selected, pkmn, heldpoke)
      return cancel_idx
    end
    return ret > pos ? ret - 1 : ret
  end

  def kif_kuray_actions(selected, pkmn, heldpoke)
    list = KIF::PCActions.available(pkmn)
    labels = list.map { |_, l| l } + [_INTL("Cancel")]
    cmd = kif_pc_pbShowCommands(_INTL("{1} is selected.", pkmn.name), labels)
    return if cmd < 0 || cmd >= list.length
    list[cmd][0].handler.call(self, pkmn, selected, heldpoke)
  end

  # KIF pbKurayRefresh: redraw the selected Pokémon and the whole box.
  def kif_refresh(selected)
    @scene.pbUpdateOverlay(selected[1], (selected[0] == -1) ? @storage.party : nil) rescue nil
    @scene.pbHardRefresh rescue nil
  end
end
