#===============================================================================
# F-POKE-08 – Per-Pokémon type override (KurayX "types overwrite")
# Source: KIF 0.20.7 014_Pokemon/001_Pokemon.rb
#   :73-75     attr_accessor :type1kuray, :type2kuray, :typeoverwrite
#   :1107-1110 type1 returns type1kuray first when typeoverwrite is set
#   :1126-1129 type2 returns type2kuray first when typeoverwrite is set
#   :1163-1197 type1kuray/type2kuray/typeoverwrite accessors
#   :2316-2318, :2379-2381 exported/imported (handled by F-PC-02 KIF_KEYS)
#
# A Pokémon whose @typeoverwrite is true uses @type1kuray / @type2kuray
# instead of its species' types (each one only when set and not :NONE).
# No menu sets these; they come with Pokémon made outside the game – e.g.
# KIF Mystery Gift 18, Fire Misbok (Ghost/Fire), and KIF imports.
#
# Battles take the battler's types from Pokemon#type1/type2
# (002_Battler_Initialize.rb:47, :81, :301), as do the Summary type icons.
#
# KIF's Pokemon#types (used by hasType?) ignored the override; this port
# matches that unless TYPES_FOLLOW is true (pending Cody's answer).
#===============================================================================
module KIF
  module TypeOverride
    TYPES_FOLLOW = false

    def self.valid?(t)
      return false if t.nil? || t == :NONE
      return GameData::Type.exists?(t) rescue false
    end
  end
end

class Pokemon
  # KIF :1163-1197
  def type1kuray=(value);    @type1kuray = value;    end
  def type2kuray=(value);    @type2kuray = value;    end
  def typeoverwrite=(value); @typeoverwrite = value; end
  def type1kuraypure;  return @type1kuray;  end
  def type2kuraypure;  return @type2kuray;  end
  def type1kuray;      return @type1kuray || self.type1; end
  def type2kuray;      return @type2kuray || self.type2; end
  def typeoverwrite;   return @typeoverwrite ? @typeoverwrite : false; end

  alias kif_tov_type1 type1 unless method_defined?(:kif_tov_type1)
  alias kif_tov_type2 type2 unless method_defined?(:kif_tov_type2)
  alias kif_tov_types types unless method_defined?(:kif_tov_types)

  def type1
    return @type1kuray if @typeoverwrite && KIF::TypeOverride.valid?(@type1kuray)
    return kif_tov_type1
  end

  def type2
    return @type2kuray if @typeoverwrite && KIF::TypeOverride.valid?(@type2kuray)
    return kif_tov_type2
  end

  def types
    return kif_tov_types unless KIF::TypeOverride::TYPES_FOLLOW && @typeoverwrite
    t1 = type1
    t2 = type2
    return (t2 && t2 != t1) ? [t1, t2] : [t1]
  end
end
