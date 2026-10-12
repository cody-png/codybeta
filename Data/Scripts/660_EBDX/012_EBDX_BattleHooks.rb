#===============================================================================
#  EBDX Battle Hooks - Toggle-guarded cosmetic aliases on PokeBattle_Battle
#===============================================================================
#  All aliases check EBDXToggle.enabled? AND that the scene is EBDX before
#  running any EBDX-specific code. This ensures zero impact when toggle is off
#  or when another player uses vanilla scene in multiplayer.
#===============================================================================

class PokeBattle_Battle
  # Compatibility layer
  def doublebattle?; return (pbSideSize(0) > 1 || pbSideSize(1) > 1); end unless method_defined?(:doublebattle?)
  def triplebattle?; return (pbSideSize(0) > 2 || pbSideSize(1) > 2); end unless method_defined?(:triplebattle?)
  def pbMaxSize(index = nil)
    return [pbSideSize(0), pbSideSize(1)].max if index.nil?
    return pbSideSize(index)
  end unless method_defined?(:pbMaxSize)

  #-----------------------------------------------------------------------------
  #  Initialize - load battle scripts data
  #-----------------------------------------------------------------------------
  alias pbInitialize_ebdx660 initialize unless method_defined?(:pbInitialize_ebdx660)
  def initialize(*args)
    if EBDXToggle.enabled?
      @midspeech = EliteBattle.get(:nextBattleScript)
      @midspeech.uniq! if @midspeech.is_a?(Array)
      @battlescene = true
    end
    return pbInitialize_ebdx660(*args)
  end

  #-----------------------------------------------------------------------------
  #  Battle loop - display warning text
  #-----------------------------------------------------------------------------
  alias pbBattleLoop_ebdx660 pbBattleLoop unless method_defined?(:pbBattleLoop_ebdx660)
  def pbBattleLoop
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      data = EliteBattle.get(:nextBattleData); data = {} if !data.is_a?(Hash)
      if data.has_key?(:WARN) && data[:WARN].is_a?(String) && !@opponent
        memb = []
        @battlers.each_with_index do |b, i|
          next if !b || i%2 == 0
          memb.push(b.name)
        end
        pbDisplay(_INTL(data[:WARN], *memb))
      end
    end
    pbBattleLoop_ebdx660
  end

  #-----------------------------------------------------------------------------
  #  Command phase - trainer speech
  #-----------------------------------------------------------------------------
  alias pbCommandPhase_ebdx660 pbCommandPhase unless method_defined?(:pbCommandPhase_ebdx660)
  def pbCommandPhase
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.pbTrainerBattleSpeech("turnStart", "rand") if @scene.respond_to?(:pbTrainerBattleSpeech)
    end
    pbCommandPhase_ebdx660
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.idleTimer = -1 if @scene.respond_to?(:idleTimer=)
    end
  end

  #-----------------------------------------------------------------------------
  #  End of round - trainer speech
  #-----------------------------------------------------------------------------
  alias pbEndOfRoundPhase_ebdx660 pbEndOfRoundPhase unless method_defined?(:pbEndOfRoundPhase_ebdx660)
  def pbEndOfRoundPhase
    ret = pbEndOfRoundPhase_ebdx660
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.pbTrainerBattleSpeech("turnEnd", "rand") if @scene.respond_to?(:pbTrainerBattleSpeech)
    end
    return ret
  end

  #-----------------------------------------------------------------------------
  #  Attack phase - trainer speech + scene wait
  #-----------------------------------------------------------------------------
  alias pbAttackPhase_ebdx660 pbAttackPhase unless method_defined?(:pbAttackPhase_ebdx660)
  def pbAttackPhase
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.pbTrainerBattleSpeech("turnAttack") if @scene.respond_to?(:pbTrainerBattleSpeech)
    end
    ret = pbAttackPhase_ebdx660
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.afterAnim = false if @scene.respond_to?(:afterAnim=)
      @scene.wait(16, true) if @scene.respond_to?(:wait)
    end
    return ret
  end

  #-----------------------------------------------------------------------------
  #  Replace battler - trainer dialogue
  #-----------------------------------------------------------------------------
  alias pbReplace_ebdx660 pbReplace unless method_defined?(:pbReplace_ebdx660)
  def pbReplace(index, *args)
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      opt = (respond_to?(:playerBattler?) && playerBattler?(@battlers[index])) ? ["last", "beforeLast"] : ["lastOpp", "beforeLastOpp"]
      @scene.pbTrainerBattleSpeech(*opt)
    end
    pbReplace_ebdx660(index, *args)
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      opt = (respond_to?(:playerBattler?) && playerBattler?(@battlers[index])) ? "afterLast" : "afterLastOpp"
      @scene.pbTrainerBattleSpeech(opt)
    end
  end

  #-----------------------------------------------------------------------------
  #  Recall and replace - trainer dialogue + sendout toggle
  #-----------------------------------------------------------------------------
  alias pbRecallAndReplace_ebdx660 pbRecallAndReplace unless method_defined?(:pbRecallAndReplace_ebdx660)
  def pbRecallAndReplace(*args)
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      @scene.pbTrainerBattleSpeech((respond_to?(:playerBattler?) && playerBattler?(@battlers[args[0]])) ? "recall" : "recallOpp")
    end
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX)
      @scene.sendingOut = true if args[0]%2 == 0 && @scene.respond_to?(:sendingOut=)
    end
    return pbRecallAndReplace_ebdx660(*args)
  end

  #-----------------------------------------------------------------------------
  #  Throw Pokeball - trainer speech
  #-----------------------------------------------------------------------------
  alias pbThrowPokeBall_ebdx660 pbThrowPokeBall unless method_defined?(:pbThrowPokeBall_ebdx660)
  def pbThrowPokeBall(*args)
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      @scene.pbTrainerBattleSpeech("beforeThrowBall")
      @scene.briefmessage = true if @scene.respond_to?(:briefmessage=)
    end
    ret = pbThrowPokeBall_ebdx660(*args)
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      @scene.pbTrainerBattleSpeech("afterThrowBall")
    end
    return ret
  end

  #-----------------------------------------------------------------------------
  #  End of battle - cleanup EBDX state
  #-----------------------------------------------------------------------------
  alias pbEndOfBattle_ebdx660 pbEndOfBattle unless method_defined?(:pbEndOfBattle_ebdx660)
  def pbEndOfBattle
    if EBDXToggle.enabled? && @scene.is_a?(PokeBattle_SceneEBDX) && @scene.respond_to?(:pbTrainerBattleSpeech)
      @scene.pbTrainerBattleSpeech("loss") if @decision == 2
    end
    ret = pbEndOfBattle_ebdx660
    if EBDXToggle.enabled?
      EliteBattle.reset(:nextBattleScript, :wildSpecies, :wildLevel, :wildForm,
                        :nextBattleBack, :nextUI, :nextBattleData,
                        :wildSpecies, :wildLevel, :wildForm, :cachedBattler, :tviewport)
      EliteBattle.set(:colorAlpha, 0)
      EliteBattle.set(:smAnim, false)
    end
    return ret
  end
end

#===============================================================================
#  GameData extensions for EBDX data retrieval
#===============================================================================
module GameData
  module ClassMethods
    unless method_defined?(:values)
      def values(skip_similar = false)
        nkey = []
        for key in self::DATA.keys
          next if skip_similar && nkey.any? { |sym| key.to_s.include?(sym.to_s) }
          nkey.push(key) if key.is_a?(Symbol)
        end
        return nkey
      end
    end
  end
  module ClassMethodsSymbols
    unless method_defined?(:values)
      def values(skip_similar = false)
        nkey = []
        for key in self::DATA.keys
          next if skip_similar && nkey.any? { |sym| key.to_s.include?(sym.to_s) }
          nkey.push(key) if key.is_a?(Symbol)
        end
        return nkey
      end
    end
  end
  module ClassMethodsIDNumbers
    unless method_defined?(:values)
      def values(skip_similar = false)
        nkey = []
        for key in self::DATA.keys
          next if skip_similar && nkey.any? { |sym| key.to_s.include?(sym.to_s) }
          nkey.push(key) if key.is_a?(Symbol)
        end
        return nkey
      end
    end
  end
end

#===============================================================================
#  Helper functions used by battle hooks
#===============================================================================
def getBattlerPokemon(battler)
  return battler.pokemon if battler.respond_to?(:pokemon)
  return nil
end

def getBattlerAltitude(battler)
  data = EliteBattle.get_data(battler.species, :Species, :ALTITUDE, (battler.form rescue 0))
  return data if !data.nil?
  return 0
end

def playBattlerCry(battler)
  return if !battler || !battler.pokemon
  GameData::Species.play_cry_from_pokemon(battler.pokemon) rescue nil
end

def shinyBattler?(battler)
  return false if !battler || !battler.pokemon
  return battler.pokemon.shiny?
end

def playerBattler?(battler)
  return false if !battler
  return battler.index % 2 == 0
end
