#===============================================================================
# F-SHINY-01 – KIF shiny colour engine: per-Pokémon colour data
# Source (verbatim logic): KIF 0.20.7
#   001_Technical/001_MKXP_Compatibility.rb:113-196  kurayKRSfunc1-3,
#                                                    kurayKRSmake, kurayRNGforChannels
#   201_Kuray/000_KurayGlobals.rb                    rollimproveshiny
#   014_Pokemon/001_Pokemon.rb:327-700               shinyValue?, shinyR/G/B?,
#                                                    shinyKRS?, shinyimprovpif?,
#                                                    head_/body_ variants, shinyOmega?
#
# Every shiny gets its own colour data, rolled lazily the first time it is
# needed and saved on the Pokémon (plain Integers/Arrays, vanilla-safe):
#   shinyValue      hue shift, -180..180
#   shinyR/G/B      channel source code 0..25 (see engine for meaning).
#                   "Normal" colour mode only uses 0..11; values > 11 are
#                   re-rolled when read in that mode (as in KIF).
#   shinyKRS        9 ints: [R incr, G incr, B incr, R semi-inv, G semi-inv,
#                   B semi-inv, R timid-black, G timid-black, B timid-black]
#   shinyimprovpif  0..3, decides PIF palette vs KIF colours (see engine)
# Fusions also keep head_* / body_* copies (set when fusing).
# Old KIF saves already contain these fields, so their shinies keep their
# exact colours.
#===============================================================================

# Increment colour (KIF kurayKRSfunc1)
def kurayKRSfunc1(krsarray)
  kurayRNG = rand(1..596)
  if kurayRNG <= 512
    krsarray.push(0)
  elsif kurayRNG <= 576
    krsarray.push(rand(-50..50))
  elsif kurayRNG <= 592
    krsarray.push(rand(-100..100))
  else
    krsarray.push(rand(-200..200))
  end
  return krsarray
end unless defined?(kurayKRSfunc1)

# Semi-inverted (KIF kurayKRSfunc2)
def kurayKRSfunc2(krsarray)
  kurayRNG = rand(1..656)
  if kurayRNG <= 512
    krsarray.push(0)
  elsif kurayRNG <= 576
    krsarray.push(1)
  elsif kurayRNG <= 640
    krsarray.push(2)
  elsif kurayRNG <= 648
    krsarray.push(3)
  else
    krsarray.push(4)
  end
  return krsarray
end unless defined?(kurayKRSfunc2)

# Timid black (KIF kurayKRSfunc3)
def kurayKRSfunc3(krsarray)
  kurayRNG = rand(1..52)
  if kurayRNG <= 32
    krsarray.push(0)
  elsif kurayRNG <= 48
    krsarray.push(1)
  else
    krsarray.push(2)
  end
  return krsarray
end unless defined?(kurayKRSfunc3)

def kurayKRSmake
  krsarray = []
  3.times { krsarray = kurayKRSfunc1(krsarray) }
  3.times { krsarray = kurayKRSfunc2(krsarray) }
  3.times { krsarray = kurayKRSfunc3(krsarray) }
  return krsarray.clone
end unless defined?(kurayKRSmake)

def kurayRNGforChannels
  if $PokemonSystem && $PokemonSystem.shinyadvanced != 2
    kurayRNG = rand(0..10000)
    if kurayRNG < 5          # weight 5
      return rand(0..11)
    elsif kurayRNG < 41      # weight 36
      return rand(0..8)
    elsif kurayRNG < 2041    # weight 2000
      return rand(0..5)
    else                     # weight 7959
      return rand(0..2)
    end
  else
    kurayRNG = rand(0..24632)
    if kurayRNG < 1          # weight 1
      return rand(0..25)
    elsif kurayRNG < 801     # weight 800
      return rand(0..19)
    elsif kurayRNG < 804     # weight 3
      return rand(0..13)
    elsif kurayRNG < 2204    # weight 1400
      return rand(0..12)
    elsif kurayRNG < 2212    # weight 8
      return rand(0..11)
    elsif kurayRNG < 2232    # weight 20
      return rand(0..8)
    elsif kurayRNG < 7832    # weight 5600
      return rand(0..5)
    else                     # weight 16800
      return rand(0..2)
    end
  end
end unless defined?(kurayRNGforChannels)

def rollimproveshiny()
  return rand(0..3)
end unless defined?(rollimproveshiny)

class Pokemon
  attr_writer :shinyValue, :shinyR, :shinyG, :shinyB, :shinyKRS, :shinyimprovpif
  attr_accessor :head_shinyhue, :body_shinyhue, :head_shinyr, :body_shinyr,
                :head_shinyg, :body_shinyg, :head_shinyb, :body_shinyb,
                :head_shinykrs, :body_shinykrs, :head_shinyimprovpif, :body_shinyimprovpif

  def shinyValue;     @shinyValue;     end
  def shinyR;         @shinyR;         end
  def shinyG;         @shinyG;         end
  def shinyB;         @shinyB;         end
  def shinyKRS;       @shinyKRS;       end
  def shinyimprovpif; @shinyimprovpif; end

  def shinyValue?
    @shinyValue = rand(0..360) - 180 if @shinyValue.nil?
    return @shinyValue
  end

  def shinyimprovpif?
    @shinyimprovpif = rollimproveshiny() if @shinyimprovpif.nil?
    return @shinyimprovpif
  end

  # KIF: in Simple/Normal colour mode codes above 11 don't exist, so they are
  # re-rolled (and saved) when read.
  def kif_channel_code(ivar)
    v = instance_variable_get(ivar)
    if v.nil? || ($PokemonSystem && $PokemonSystem.shinyadvanced != 2 && v > 11)
      v = kurayRNGforChannels
      instance_variable_set(ivar, v)
    end
    return v
  end

  def shinyR?; kif_channel_code(:@shinyR); end
  def shinyG?; kif_channel_code(:@shinyG); end
  def shinyB?; kif_channel_code(:@shinyB); end

  def shinyKRS?
    @shinyKRS = kurayKRSmake if @shinyKRS.nil?
    return @shinyKRS
  end

  def head_shinyhue?;       @head_shinyhue ||= rand(0..360) - 180;  end
  def body_shinyhue?;       @body_shinyhue ||= rand(0..360) - 180;  end
  def head_shinyimprovpif?; @head_shinyimprovpif ||= rollimproveshiny(); end
  def body_shinyimprovpif?; @body_shinyimprovpif ||= rollimproveshiny(); end
  def head_shinyr?;         @head_shinyr ||= kurayRNGforChannels;   end
  def body_shinyr?;         @body_shinyr ||= kurayRNGforChannels;   end
  def head_shinyg?;         @head_shinyg ||= kurayRNGforChannels;   end
  def body_shinyg?;         @body_shinyg ||= kurayRNGforChannels;   end
  def head_shinyb?;         @head_shinyb ||= kurayRNGforChannels;   end
  def body_shinyb?;         @body_shinyb ||= kurayRNGforChannels;   end
  def head_shinykrs?;       @head_shinykrs ||= kurayKRSmake;        end
  def body_shinykrs?;       @body_shinykrs ||= kurayKRSmake;        end

  # "Give more data to shiny nexus without passing 10000 arguments" (KIF)
  def shinyOmega?
    return {
      "pif_shiny"  => self.shinyimprovpif?,
      "body_shiny" => @body_shiny,
      "head_shiny" => @head_shiny,
      "dexNum"     => self.dexNum
    }
  end

  # Copies all KIF colour data of a single (unfused) Pokémon's main fields.
  def kif_shiny_colors
    return { :hue => shinyValue?, :pif => shinyimprovpif?, :r => shinyR?, :g => shinyG?,
             :b => shinyB?, :krs => shinyKRS?.clone }
  end

  def kif_set_shiny_colors(c)
    @shinyValue = c[:hue]; @shinyimprovpif = c[:pif]
    @shinyR = c[:r]; @shinyG = c[:g]; @shinyB = c[:b]; @shinyKRS = c[:krs].clone
  end

  def kif_reroll_shiny_colors
    @shinyValue = rand(0..360) - 180
    @shinyimprovpif = rollimproveshiny()
    @shinyR = kurayRNGforChannels
    @shinyG = kurayRNGforChannels
    @shinyB = kurayRNGforChannels
    @shinyKRS = kurayKRSmake
  end
end
