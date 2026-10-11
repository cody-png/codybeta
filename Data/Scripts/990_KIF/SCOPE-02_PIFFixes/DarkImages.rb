#===============================================================================
# SCOPE-02 – PIF fix: dark mode images this install doesn't ship
# 6.8.2 loads cursor_command_dark / cursor_fight_dark / panel_blank_dark when
# its dark mode (PokéNav setting, also KIF's Dark Mode switch) is on; the
# Kanto build has no such files, so battle buttons and party panels vanished.
# A missing "_dark" image falls back to the normal one. Always on: PIF's own
# setting needs it whatever the modules say. (Moved from F-UI-11, 2026-10-11.)
#===============================================================================
class AnimatedBitmap
  alias kif_dm_initialize initialize unless method_defined?(:kif_dm_initialize)

  def initialize(file, *args)
    if file.is_a?(String) && file.end_with?("_dark") && !pbResolveBitmap(file)
      file = file[0...-5]
    end
    kif_dm_initialize(file, *args)
  end
end
