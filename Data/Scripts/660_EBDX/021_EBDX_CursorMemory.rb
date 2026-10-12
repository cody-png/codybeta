#===============================================================================
# EBDX Command Menu Cursor Memory
#===============================================================================
# Patches pbCommandMenuEBDX so the command cursor remembers its last position
# between turns (e.g. if you used Bag last turn, cursor starts on Bag next turn).
#
# Root cause: pbCommandMenuEBDX always sets @commandWindow.index = 0 and never
# reads/writes @lastCmd, unlike the vanilla pbCommandMenuEx which does both.
#===============================================================================

if defined?(PokeBattle_SceneEBDX)
  class PokeBattle_SceneEBDX
    def pbCommandMenuEBDX(idxBattler, firstAction)
      @commandWindow.refreshCommands(idxBattler) if @commandWindow.respond_to?(:refreshCommands)
      @commandWindow.showPlay if @commandWindow.respond_to?(:showPlay)

      # Restore cursor to last used position for this battler slot (after refresh,
      # so refresh can't clobber our index).
      if @commandWindow.respond_to?(:index=)
        @commandWindow.index = (@lastCmd && @lastCmd[idxBattler]) || 0
      end

      numCommands = @commandWindow.indexes.length rescue 4
      ret = -1
      loop do
        pbUpdate(@commandWindow)
        if Input.trigger?(Input::LEFT)
          @commandWindow.index = (@commandWindow.index - 1) % numCommands if @commandWindow.respond_to?(:index=)
          pbSEPlay("EBDX/SE_Select1", 80)
        elsif Input.trigger?(Input::RIGHT)
          @commandWindow.index = (@commandWindow.index + 1) % numCommands if @commandWindow.respond_to?(:index=)
          pbSEPlay("EBDX/SE_Select1", 80)
        elsif Input.trigger?(Input::UP)
          @commandWindow.index = (@commandWindow.index - 1) % numCommands if @commandWindow.respond_to?(:index=)
          pbSEPlay("EBDX/SE_Select1", 80)
        elsif Input.trigger?(Input::DOWN)
          @commandWindow.index = (@commandWindow.index + 1) % numCommands if @commandWindow.respond_to?(:index=)
          pbSEPlay("EBDX/SE_Select1", 80)
        elsif Input.trigger?(Input::USE)
          ret = @commandWindow.indexes[@commandWindow.index] rescue @commandWindow.index
          pbSEPlay("EBDX/SE_Select2", 80)
          break
        elsif Input.trigger?(Input::BACK)
          if firstAction
            pbPlayBuzzerSE
          else
            ret = -1
            pbPlayCancelSE
            break
          end
        end
      end

      # Save cursor position so it's restored next turn
      @lastCmd[idxBattler] = ret if @lastCmd && ret >= 0

      @commandWindow.hidePlay if @commandWindow.respond_to?(:hidePlay)
      return ret
    end

  end
end
