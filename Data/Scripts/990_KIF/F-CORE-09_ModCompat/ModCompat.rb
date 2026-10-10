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

KIF::ModCompat.write_version
