#===============================================================================
# SCOPE-02 – PIF fix: no Exp for a Pokémon that switched out
# pbAbilitiesOnSwitchOut marks a switched-out battler as fainted ("Treat self
# as fainted", Essentials) and the replacement only comes in later, so the
# Exp check at the end of the move (pbGainExp: fainted? or captured) paid out
# for a foe that left through Wimp Out / Emergency Exit (Cody's playthrough,
# 2026-10-11: "Minipod went back to Rick!" then 344 Exp). Same for any other
# forced switch of a trainer's Pokémon. The battler is tagged while it is
# only switched out; pbGainExp leaves it alone until a real Pokémon fills
# the slot again. Always on (a bug fix; happens with every module Off too).
#===============================================================================
class PokeBattle_Battler
  attr_accessor :kif_switched_out

  alias kif_so_pbAbilitiesOnSwitchOut pbAbilitiesOnSwitchOut unless method_defined?(:kif_so_pbAbilitiesOnSwitchOut)
  def pbAbilitiesOnSwitchOut(*args)
    was_fainted = fainted?
    ret = kif_so_pbAbilitiesOnSwitchOut(*args)
    @kif_switched_out = true unless was_fainted   # a real KO keeps its Exp
    return ret
  end

  alias kif_so_pbInitialize pbInitialize unless method_defined?(:kif_so_pbInitialize)
  def pbInitialize(*args)
    @kif_switched_out = false
    return kif_so_pbInitialize(*args)
  end
end

class PokeBattle_Battle
  alias kif_so_pbGainExp pbGainExp unless method_defined?(:kif_so_pbGainExp)
  def pbGainExp
    held = []
    @battlers.each do |b|
      next unless b && b.kif_switched_out && b.fainted?
      held << [b, b.participants]
      b.participants = []
    end
    return kif_so_pbGainExp if held.empty?
    begin
      return kif_so_pbGainExp
    ensure
      held.each { |b, p| b.participants = p }
    end
  end
end
