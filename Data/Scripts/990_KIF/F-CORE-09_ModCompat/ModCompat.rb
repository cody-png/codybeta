#===============================================================================
# F-CORE-09 – Mod compatibility (KIF 1.0, 2026-10-10)
#   Mods written for KIF 0.20.7 (and the community Mod Manager 2.0 catalog,
#   github KIF-Mods/mods) call a few KIF 0.20.7 / PIF 6.4.5 methods that
#   PIF 6.8.2 renamed or dropped. They are provided here under their old
#   names, wired to 6.8.2's own code, so those mods load and their hooks run.
#   Found by loading every catalog mod in the test kit (PORT_LOG, mod audit).
#
#   kurayEncounterInit  KIF 0.20.7 012_Overworld/001_Overworld.rb:234 – the
#                       wild Pokémon of a step encounter. 6.8.2 calls it
#                       generateWildEncounter; the game now goes through the
#                       old name, so a mod hooking it runs (Ghost QoL).
#   MessageTypes.set    PIF 6.4.5 / KIF 003_Intl_Messages.rb:691 – mods name
#                       their new items with it (Player Housing, Splicers,
#                       Alpha Encounters).
#   ability2 & co.      PIF 6.4.5 052_AddOns/DoubleAbilities.rb (in KIF
#                       0.20.7): a second ability, only while switch 773
#                       (SWITCH_DOUBLE_ABILITIES) is on. 6.8.2 dropped the
#                       methods; mods still hook them (Master Splicer). The
#                       methods are back with KIF's logic; the battle side
#                       of double abilities is not (nothing in KIF Beta
#                       turns the switch on).
#   PokemonSystem       17 KIF 0.20.7 options/flags 6.8.2 doesn't have
#                       (016_UI/015_UI_Options.rb:1-290), with KIF's
#                       defaults; is_in_battle is true while a battle runs
#                       (KIF 001_Overworld_BattleStarting.rb:268, 003_Battle_
#                       StartAndEnd.rb:357). Alpha Encounters' raids set it.
#   $game_temp.followers  Essentials v21's follower list; Overworld Encounters
#                       walks it while waiting for move routes. 6.8.2 has no
#                       such list (its followers are dependent events), so
#                       an empty one is given: nothing to wait for.
#   Data/VERSION        mods tell KIF from PIF by its major number (KIF < 5).
#                       6.8.2 doesn't use the file; KIF writes its own
#                       version there before mods load (6 Pokémon Gym
#                       Leaders loads its folder only on KIF).
#===============================================================================
module KIF
  module ModCompat
    VERSION_FILE = "Data/VERSION"

    def self.write_version
      want = KIF::PORT_VERSION.to_s
      have = File.exist?(VERSION_FILE) ? File.read(VERSION_FILE).strip : nil
      File.open(VERSION_FILE, "wb") { |f| f.write(want) } if have != want
    rescue StandardError => e
      KIF.log("Data/VERSION not written (#{e.class}: #{e.message})")
    end
  end
end

#-------------------------------------------------------------------------------
# kurayEncounterInit <-> generateWildEncounter
#-------------------------------------------------------------------------------
alias kif_compat_generateWildEncounter generateWildEncounter unless defined?(kif_compat_generateWildEncounter)

def kurayEncounterInit(encounter_type)
  return kif_compat_generateWildEncounter(encounter_type)
end

def generateWildEncounter(encounter_type)
  return kurayEncounterInit(encounter_type)
end

class PokemonEncounters
  # KIF called it on $PokemonEncounters for the 2nd/3rd Pokémon
  def kurayEncounterInit(encounter_type)
    return Object.instance_method(:kurayEncounterInit).bind(self).call(encounter_type)
  end
end

#-------------------------------------------------------------------------------
# MessageTypes.set
#-------------------------------------------------------------------------------
module MessageTypes
  unless respond_to?(:set)
    # KIF wrote only the language table; with no language file loaded
    # (English) 6.8.2 reads the base table, so both get the text
    def self.set(type, id, value)
      @@messages.set(type, id, value)
      @@messagesFallback.set(type, id, value)
    end
  end
end

#-------------------------------------------------------------------------------
# Double-ability methods (KIF 0.20.7 052_AddOns/DoubleAbilities.rb:21-35,
# :135-205), only where 6.8.2 has none
#-------------------------------------------------------------------------------
module KIF
  module ModCompat
    def self.double_abilities?
      return !!($game_switches && $game_switches[SWITCH_DOUBLE_ABILITIES])
    rescue StandardError
      return false
    end
  end
end

class Pokemon
  attr_writer :ability2_index unless method_defined?(:ability2_index=)

  unless method_defined?(:ability2_index)
    def ability2_index
      return nil unless KIF::ModCompat.double_abilities?
      @ability2_index = (@personalID & 1) if !@ability2_index
      return @ability2_index
    end
  end

  unless method_defined?(:ability2_id)
    def ability2_id
      return nil unless KIF::ModCompat.double_abilities?
      if !@ability2
        sp_data = species_data
        abil_index = ability_index
        if abil_index >= 2   # hidden ability
          @ability2 = sp_data.hidden_abilities[abil_index - 2]
          abil_index = (@personalID & 1) if !@ability2
        end
        @ability2 = sp_data.abilities[abil_index] || sp_data.abilities[0] if !@ability2
      end
      return @ability2
    end
  end

  unless method_defined?(:ability2)
    def ability2
      return nil unless KIF::ModCompat.double_abilities?
      return GameData::Ability.try_get(ability2_id)
    end
  end

  unless method_defined?(:ability2=)
    def ability2=(value)
      return unless KIF::ModCompat.double_abilities?
      return if value && !GameData::Ability.exists?(value)
      @ability2 = value ? GameData::Ability.get(value).id : value
    end
  end
end

class PokeBattle_Battler
  attr_writer :ability2_id unless method_defined?(:ability2_id=)

  unless method_defined?(:ability2_id)
    def ability2_id
      return @ability2_id
    end
  end

  unless method_defined?(:ability2)
    def ability2
      return nil unless KIF::ModCompat.double_abilities?
      return GameData::Ability.try_get(@ability2_id)
    end
  end

  unless method_defined?(:ability2=)
    def ability2=(value)
      return unless KIF::ModCompat.double_abilities?
      a = GameData::Ability.try_get(value)
      @ability2_id = a ? a.id : nil
    end
  end

  unless method_defined?(:ability2Name)
    def ability2Name
      a = ability2
      return a ? a.name : ""
    end
  end
end

#-------------------------------------------------------------------------------
# KIF 0.20.7 PokemonSystem attributes that 6.8.2 / KIF Beta don't define
#-------------------------------------------------------------------------------
class PokemonSystem
  {
    :autobattleshortcut => 0, :darkmode => 1, :globalvalues => 0, :is_in_battle => false,
    :kurayindividcustomsprite => 1, :kuraynormalshiny => 0, :playerage_temp => 0,
    :quicksurf => 0, :raiser => 1, :savefolder => 0, :sb_loopbreaker => 0,
    :sb_soullinked => 0, :skipcaughtnickname => 0, :speedtoggle => 0, :speedvalue => 2,
    :speedvaluedef => 0, :optionsnames => nil
  }.each do |name, default|
    next if method_defined?(name)
    ivar = :"@#{name}"
    define_method(name) do
      v = instance_variable_get(ivar)
      if v.nil?
        v = (name == :optionsnames) ? Array.new(12) { |i| "Slot #{i + 1}" } : default
        instance_variable_set(ivar, v)
      end
      v
    end
    define_method(:"#{name}=") { |v| instance_variable_set(ivar, v) }
  end
end

class PokeBattle_Battle
  alias kif_compat_pbStartBattle pbStartBattle unless method_defined?(:kif_compat_pbStartBattle)

  def pbStartBattle(*args)
    $PokemonSystem.is_in_battle = true if $PokemonSystem
    begin
      return kif_compat_pbStartBattle(*args)
    ensure
      $PokemonSystem.is_in_battle = false if $PokemonSystem
    end
  end
end

#-------------------------------------------------------------------------------
# $game_temp.followers (Essentials v21) - empty
#-------------------------------------------------------------------------------
module KIF
  module ModCompat
    class NoFollowers
      include Enumerable
      def each_follower; end
      def each; end
      def length; 0; end
      def empty?; true; end
    end
  end
end

class Game_Temp
  unless method_defined?(:followers)
    def followers
      @kif_no_followers ||= KIF::ModCompat::NoFollowers.new
    end
  end
end

KIF::ModCompat.write_version
