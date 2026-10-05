#===============================================================================
# F-BATTLE-06 – Optional mechanics pack (Bluewuppo, with a fix by Reïzod)
# Source: KIF 0.20.7
#   016_UI/015_UI_Options.rb:2353-2384 (Battles), :2818-2824 (Others)
#   010_Data/002_PBS data/003_Type.rb:116-130        Bug / Ice type buffs
#   012_Overworld/001_Overworld.rb:87-129             Overworld Poison
#   011_Battle/002_Move/003_Move_Usage_Calculations.rb:402-405, :434-441
#     Hail/Snow Defense boost for Ice types, Frostbite and Drowsy damage cut
#   011_Battle/001_Battler/009_Battler_UseMove_SuccessChecks.rb:202-249
#     Drowsy: 50% chance to act (25% in hail)
#   011_Battle/003_Battle/012_Battle_Phase_EndOfRound.rb:98, :409-418
#     Snow: no hail damage; Frostbite: 1/16 HP each turn
#   011_Battle/001_Battler/001_PokeBattle_Battler.rb:116  Truant kept (Drowsy)
#   message changes in 004_Battler_Statuses.rb, 005_Move_Effects_000-07F.rb,
#   002_PokeBattle_Battle.rb, 012_Battle_Phase_EndOfRound.rb,
#   003_BattleHandlers_Abilities.rb:1395, 013_Items/002_Item_Effects.rb:481
#
# Options (per save)
#   Battles > "Modern Hail" Off / Hail / Snow: with Hail or Snow, Ice types get
#     x1.5 Defense against physical moves (and Psyshock-style moves) in hail;
#     Snow also removes the hail damage and calls it snow.
#   Battles > "Frostbite": Frozen becomes Frostbite – 1/16 HP lost each turn,
#     special moves deal half damage (Guts ignores it).
#   Battles > "Drowsy": Asleep becomes Drowsy – each turn a 50% chance to act
#     (25% in hail), all its moves deal half damage (Guts ignores it). It still
#     wears off like sleep.
#   Battles > "Bug Type Buffs" Off / Defensive / + Offensive: Bug resists
#     Psychic, Dark and Fairy; + Offensive also makes Bug hit Fairy x2.
#   Battles > "Ice Type Buffs": Ice resists Water and Flying.
#   Others > "Overworld Poison" Off / On / On+Healing: On – Poison Heal and
#     Magic Guard also take no poison damage while walking (Immunity already
#     doesn't); On+Healing – Poison Heal heals 1 HP instead.
#
# Choices (Cody, 2026-10-05):
#   * Frostbite doesn't stop the Pokémon from moving (Gen 9 style, as the
#     option text says). In KIF it still couldn't move 80% of the time, like
#     Frozen. It is cured the same ways (Fire moves that thaw, Ice Heal, ...).
#
# 6.8.2 adaptations / notes:
#   * No copies. The status names stay :FROZEN / :SLEEP (as KIF), so the
#     status icons are unchanged. The renamed battle texts are swapped where
#     _INTL looks the text up (KIF::Mechanics::TEXTS), so every place that
#     prints them – battle, Heal Bell, Ice Heal – changes at once.
#   * KIF's Hail check read `physicalMove? || @function = "122"` – an
#     assignment that made every move count and rewrote the move's function
#     code. Fixed to `== "122"` (Psyshock / Psystrike / Secret Sword).
#   * KIF's "is fast asleep." never showed with Drowsy Off (a `when :SLEEP &&`
#     slip); here it shows as in PIF.
#   * Frostbite damage comes just before Taunt ticks down in the end-of-round
#     phase (KIF: just after burn damage, before Nightmare, Curse and binding
#     moves). Same damage, slightly later in the round.
#   * Not ported (edge cases needing copies of long base methods): KIF let a
#     drowsy/frostbitten Pokémon use Pursuit on a switching foe, and kept a
#     multi-hit move going if its user fell asleep mid-move.
#   * KIF's AI changes for Drowsy/Frostbite belong with DemICE's AI
#     (F-BATTLE-03), which replaces those AI methods.
#===============================================================================
KIF::Options.define(:modernhail, 0, :save)
KIF::Options.define(:frostbite, 0, :save)
KIF::Options.define(:drowsy, 0, :save)
KIF::Options.define(:bugbuff, 0, :save)
KIF::Options.define(:icebuff, 0, :save)
KIF::Options.define(:walkingpoison, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Modern Hail"), [_INTL("Off"), _INTL("Hail"), _INTL("Snow")],
                 proc { $PokemonSystem.modernhail },
                 proc { |value| $PokemonSystem.modernhail = value },
                 [_INTL("Vanilla hail."),
                  _INTL("Ice types receive a defensive boost during hail."),
                  _INTL("Hail becomes Snow, behaves like Gen 9+.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Frostbite"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.frostbite },
                 proc { |value| $PokemonSystem.frostbite = value },
                 [_INTL("Vanilla Frozen Status."),
                  _INTL("Frostbite Status from Gen 9+ replaces Frozen Status.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Drowsy"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.drowsy },
                 proc { |value| $PokemonSystem.drowsy = value },
                 [_INTL("Vanilla Sleep Status."),
                  _INTL("Drowsy Status from Gen 9+ replaces Sleep Status.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Bug Type Buffs"), [_INTL("Off"), _INTL("Defensive"), _INTL("+ Offensive")],
                 proc { $PokemonSystem.bugbuff },
                 proc { |value| $PokemonSystem.bugbuff = value },
                 [_INTL("Vanilla Bug Types."),
                  _INTL("Bug Types resist Fairy, Psychic, and Dark."),
                  _INTL("Fairy Types are weak to Bug Type Moves.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Ice Type Buffs"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.icebuff },
                 proc { |value| $PokemonSystem.icebuff = value },
                 [_INTL("Vanilla Ice Types."),
                  _INTL("Ice Types now resist Water and Flying.")])
}
KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Overworld Poison"), [_INTL("Off"), _INTL("On"), _INTL("On+Healing")],
                 proc { $PokemonSystem.walkingpoison },
                 proc { |value| $PokemonSystem.walkingpoison = value },
                 [_INTL("Everyone takes dmg on overworld poison."),
                  _INTL("Some abilities immune to dmg on overworld poison."),
                  _INTL("Some abilities heal instead of taking dmg on overworld poison.")])
}

module KIF
  module Mechanics
    def self.opt(name)
      return 0 unless $PokemonSystem && $PokemonSystem.respond_to?(name)
      return $PokemonSystem.send(name).to_i
    end

    def self.hail;          opt(:modernhail);    end   # 0 off, 1 hail, 2 snow
    def self.snow?;         hail == 2;           end
    def self.frostbite?;    opt(:frostbite) != 0; end
    def self.drowsy?;       opt(:drowsy) != 0;   end
    def self.bugbuff;       opt(:bugbuff);       end
    def self.icebuff?;      opt(:icebuff) != 0;  end
    def self.walkingpoison; opt(:walkingpoison); end

    # base text => [option test, KIF text]
    TEXTS = {
      "{1} is already asleep!"         => [:drowsy?, "{1} is already drowsy!"],
      "{1} fell asleep!"               => [:drowsy?, "{1} starts to feel drowsy!"],
      "{1} is fast asleep."            => [:drowsy?, "{1} is drowsy."],
      "{1} made {2} drowsy!"           => [:drowsy?, "{2} is getting tired!"],
      "{1} was woken from sleep."      => [:drowsy?, "{1} is awake."],
      "{1}'s {2} made {3} fall asleep!" => [:drowsy?, "{1}'s {2} made {3} drowsy!"],
      "{1} is already frozen solid!"   => [:frostbite?, "{1} is already frostbitten!"],
      "{1} cannot be frozen solid!"    => [:frostbite?, "{1} cannot be frostbitten!"],
      "{1} cannot be frozen solid because of {2}'s {3}!" =>
                                          [:frostbite?, "{1} cannot be frostbitten because of {2}'s {3}!"],
      "{1} was frozen solid!"          => [:frostbite?, "{1} was frostbitten!"],
      "{1} is frozen solid!"           => [:frostbite?, "{1} was hurt by its frostbite!"],
      "{1} thawed out!"                => [:frostbite?, "{1}'s frostbite was healed!"],
      "{1} was thawed out."            => [:frostbite?, "{1}'s frostbite was healed."],
      "It started to hail!"            => [:snow?, "It started to snow!"],
      "The hail stopped."              => [:snow?, "The snow stopped."],
      "The hail is crashing down."     => [:snow?, "The snow is falling down."]
    }

    def self.reword(text)
      entry = TEXTS[text]
      return nil unless entry
      return send(entry[0]) ? entry[1] : nil
    rescue
      nil
    end

    @drowsy_acts = false
    @frostbite_acts = false
    @walking = false
    class << self
      attr_accessor :drowsy_acts, :frostbite_acts, :walking
    end
  end
end

#-------------------------------------------------------------------------------
# Renamed texts
#-------------------------------------------------------------------------------
alias kif_mech__INTL _INTL unless defined?(kif_mech__INTL)

def _INTL(*arg)
  if arg[0].is_a?(String) && KIF::Mechanics::TEXTS.key?(arg[0])
    new_text = KIF::Mechanics.reword(arg[0])
    arg = [new_text] + arg[1..-1] if new_text
  end
  return kif_mech__INTL(*arg)
end

#-------------------------------------------------------------------------------
# Bug / Ice type buffs (KIF 003_Type.rb:116-130)
#-------------------------------------------------------------------------------
module Effectiveness
  class << self
    alias kif_mech_calculate_one calculate_one unless method_defined?(:kif_mech_calculate_one)

    def calculate_one(attack_type, defend_type)
      ret = kif_mech_calculate_one(attack_type, defend_type)
      if KIF::Mechanics.icebuff? && defend_type == :ICE && [:WATER, :FLYING].include?(attack_type)
        ret = NOT_VERY_EFFECTIVE_ONE
      end
      if KIF::Mechanics.bugbuff != 0 && defend_type == :BUG && [:PSYCHIC, :DARK, :FAIRY].include?(attack_type)
        ret = NOT_VERY_EFFECTIVE_ONE
      end
      if KIF::Mechanics.bugbuff == 2 && defend_type == :FAIRY && attack_type == :BUG
        ret = SUPER_EFFECTIVE_ONE
      end
      return ret
    end
  end
end

#-------------------------------------------------------------------------------
# Damage: Hail/Snow Defense, Frostbite, Drowsy
#-------------------------------------------------------------------------------
class PokeBattle_Move
  alias kif_mech_pbCalcDamageMultipliers pbCalcDamageMultipliers unless method_defined?(:kif_mech_pbCalcDamageMultipliers)
  alias kif_mech_usableWhenAsleep? usableWhenAsleep? unless method_defined?(:kif_mech_usableWhenAsleep?)
  alias kif_mech_thawsUser? thawsUser? unless method_defined?(:kif_mech_thawsUser?)

  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    kif_mech_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    if KIF::Mechanics.hail != 0 && @battle.pbWeather == :Hail &&
       target.pbHasType?(:ICE) && (physicalMove? || @function == "122")
      multipliers[:defense_multiplier] *= 1.5
    end
    if KIF::Mechanics.frostbite? && user.status == :FROZEN && specialMove? &&
       !user.hasActiveAbility?(:GUTS)
      multipliers[:final_damage_multiplier] /= 2
    end
    if KIF::Mechanics.drowsy? && user.status == :SLEEP && !user.hasActiveAbility?(:GUTS)
      multipliers[:final_damage_multiplier] /= 2
    end
  end

  # While a drowsy Pokémon gets to act, its move counts as usable asleep
  def usableWhenAsleep?
    return true if KIF::Mechanics.drowsy_acts
    return kif_mech_usableWhenAsleep?
  end

  # While a frostbitten Pokémon acts, the frozen check is passed
  def thawsUser?
    return true if KIF::Mechanics.frostbite_acts
    return kif_mech_thawsUser?
  end
end

#-------------------------------------------------------------------------------
# Drowsy / Frostbite turns (KIF 009_Battler_UseMove_SuccessChecks.rb:202-249)
#-------------------------------------------------------------------------------
class PokeBattle_Battler
  alias kif_mech_pbTryUseMove pbTryUseMove unless method_defined?(:kif_mech_pbTryUseMove)
  alias kif_mech_pbContinueStatus pbContinueStatus unless method_defined?(:kif_mech_pbContinueStatus)
  alias kif_mech_takesHailDamage? takesHailDamage? unless method_defined?(:kif_mech_takesHailDamage?)
  alias kif_mech_status= status= unless method_defined?(:kif_mech_status=)

  def pbTryUseMove(choice, move, specialUsage, skipAccuracyCheck)
    drowsy_acts = false
    frost_acts = false
    if !skipAccuracyCheck && move
      if @status == :SLEEP && KIF::Mechanics.drowsy? && @statusCount > 1 &&
         !move.usableWhenAsleep?
        fail_chance = (@battle.pbWeather == :Hail) ? 75 : 50
        drowsy_acts = @battle.pbRandom(100) >= fail_chance
      elsif @status == :FROZEN && KIF::Mechanics.frostbite?
        frost_acts = true
      end
    end
    old_d = KIF::Mechanics.drowsy_acts
    old_f = KIF::Mechanics.frostbite_acts
    KIF::Mechanics.drowsy_acts = drowsy_acts
    KIF::Mechanics.frostbite_acts = frost_acts
    begin
      return kif_mech_pbTryUseMove(choice, move, specialUsage, skipAccuracyCheck)
    ensure
      KIF::Mechanics.drowsy_acts = old_d
      KIF::Mechanics.frostbite_acts = old_f
    end
  end

  # A drowsy Pokémon that gets to act shows no "is drowsy." first (KIF)
  def pbContinueStatus(*args, &block)
    return if KIF::Mechanics.drowsy_acts && @status == :SLEEP && !block
    return kif_mech_pbContinueStatus(*args, &block)
  end

  def takesHailDamage?
    return false if KIF::Mechanics.snow?
    return kif_mech_takesHailDamage?
  end

  # Drowsy: waking up doesn't reset Truant (KIF 001_PokeBattle_Battler.rb:116)
  def status=(value)
    truant = @effects[PBEffects::Truant]
    self.kif_mech_status = value
    @effects[PBEffects::Truant] = truant if KIF::Mechanics.drowsy?
  end
end

#-------------------------------------------------------------------------------
# Frostbite damage each round (KIF 012_Battle_Phase_EndOfRound.rb:409-418)
# Runs at the first end-of-round countdown (Taunt), after status damage.
#-------------------------------------------------------------------------------
class PokeBattle_Battle
  alias kif_mech_pbEORCountDownBattlerEffect pbEORCountDownBattlerEffect unless method_defined?(:kif_mech_pbEORCountDownBattlerEffect)

  def pbEORCountDownBattlerEffect(priority, effect, &block)
    if @kif_frostbite_turn != @turnCount
      @kif_frostbite_turn = @turnCount
      kif_frostbite_damage(priority) if KIF::Mechanics.frostbite?
    end
    return kif_mech_pbEORCountDownBattlerEffect(priority, effect, &block)
  end

  def kif_frostbite_damage(priority)
    priority.each do |b|
      next if b.fainted? || b.status != :FROZEN || !b.takesIndirectDamage?
      oldHP = b.hp
      dmg = (Settings::MECHANICS_GENERATION >= 7) ? b.totalhp / 16 : b.totalhp / 8
      b.pbContinueStatus { b.pbReduceHP(dmg, false) }
      b.pbItemHPHealCheck
      b.pbAbilitiesOnDamageTaken(oldHP)
      b.pbFaint if b.fainted?
    end
  end
end

#-------------------------------------------------------------------------------
# Overworld Poison (KIF 012_Overworld/001_Overworld.rb:94-126)
# 6.8.2's step handler skips Immunity; while it runs, Poison Heal and Magic
# Guard count as Immunity too (On / On+Healing). Poison Heal healing follows.
#-------------------------------------------------------------------------------
class Pokemon
  alias kif_mech_hasAbility? hasAbility? unless method_defined?(:kif_mech_hasAbility?)

  def hasAbility?(check_ability = nil)
    if KIF::Mechanics.walking && check_ability == :IMMUNITY && self.status == :POISON
      return true if kif_mech_hasAbility?(:POISONHEAL) || kif_mech_hasAbility?(:MAGICGUARD)
    end
    return kif_mech_hasAbility?(check_ability)
  end
end

module KIF
  module Mechanics
    def self.install_step_hook
      ev = Events.onStepTakenTransferPossible
      return if ev.respond_to?(:kif_mech_trigger)
      class << ev
        alias_method :kif_mech_trigger, :trigger

        def trigger(*args)
          mode = KIF::Mechanics.walkingpoison
          return kif_mech_trigger(*args) if mode == 0
          handled = args[1]
          old = KIF::Mechanics.walking
          KIF::Mechanics.walking = true
          begin
            kif_mech_trigger(*args)
          ensure
            KIF::Mechanics.walking = old
          end
          KIF::Mechanics.poison_heal_step if mode == 2 && !(handled.is_a?(Array) && handled[0])
        end
      end
    end

    # On+Healing: Poison Heal restores 1 HP every 4 steps (same steps as damage)
    def self.poison_heal_step
      return if $game_switches[SWITCH_GAME_DIFFICULTY_EASY]
      return unless Settings::POISON_IN_FIELD && $PokemonGlobal.stepcount % 4 == 0
      healed = false
      $Trainer.able_party.each do |pkmn|
        next unless pkmn.status == :POISON && pkmn.hasAbility?(:POISONHEAL)
        next if pkmn.hp >= pkmn.totalhp
        hurt = $Trainer.able_party.any? { |p| p.status == :POISON && !p.hasAbility?(:IMMUNITY) &&
                                              !p.hasAbility?(:POISONHEAL) && !p.hasAbility?(:MAGICGUARD) }
        pbFlash(Color.new(73, 164, 163, 128), 8) if !healed && !hurt
        healed = true
        pkmn.hp += 1
      end
    end
  end
end
KIF::Mechanics.install_step_hook
