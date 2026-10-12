#===============================================================================
#  EBDX Environment Configurations
#  Adapted from Elite Battle DX Environments.rb
#===============================================================================
module EnvironmentEBDX
  #-----------------------------------------------------------------------------
  # Default outdoor environment
  #-----------------------------------------------------------------------------
  OUTDOOR = {
    "backdrop" => "Field",
    "sky" => true,
    "outdoor" => true,
    "trees" => {
      :elements => 9,
      :x => [150, 271, 78, 288, 176, 42, 118, 348, 321],
      :y => [108, 117, 118, 126, 126, 128, 136, 136, 145],
      :zoom => [0.44, 0.44, 0.59, 0.59, 0.59, 0.64, 0.85, 0.7, 1],
      :mirror => [false, false, true, true, true, false, false, true, false]
    }
  }
  #-----------------------------------------------------------------------------
  # Default indoor environment
  #-----------------------------------------------------------------------------
  INDOOR = {
    "backdrop" => "IndoorA",
    "outdoor" => false,
    "img001" => {
      :bitmap => "decor007",
      :oy => 0, :z => 1, :flat => true, :scrolling => true, :speed => 0.5
    },
    "img002" => {
      :bitmap => "decor008",
      :oy => 0, :z => 1, :flat => true, :scrolling => true, :direction => -1
    },
    "lightsA" => true
  }
  #-----------------------------------------------------------------------------
  # Cave environment
  #-----------------------------------------------------------------------------
  CAVE = {
    "backdrop" => "Cave",
    "outdoor" => false,
    "img001" => {
      :scrolling => true, :speed => 2, :direction => -1,
      :bitmap => "decor006",
      :oy => 0, :z => 3, :flat => true, :opacity => 155
    },
    "img002" => {
      :scrolling => true, :speed => 1, :direction => 1,
      :bitmap => "decor009",
      :oy => 0, :z => 3, :flat => true, :opacity => 96
    },
    "img003" => {
      :scrolling => true, :speed => 0.5, :direction => 1,
      :bitmap => "fog",
      :oy => 0, :z => 4, :flat => true
    },
    "img004" => {
      :bitmap => "darkFog", :scrolling => true, :speed => 0.3, :direction => -1,
      :oy => 0, :z => 2, :flat => true, :opacity => 65
    },
  }
  #-----------------------------------------------------------------------------
  # Water environment
  #-----------------------------------------------------------------------------
  WATER = {
    "backdrop" => "Water",
    "sky"      => true,
    "water"    => true,
    "outdoor"  => true,
    "img001"   => { :bitmap => "mountainB", :x => 50,  :y => 88, :z => 0, :opacity => 120 },
    "img002"   => { :bitmap => "mountainB", :x => 290, :y => 95, :z => 0, :opacity => 90, :mirror => true }
  }
  #-----------------------------------------------------------------------------
  # Forest environment
  #-----------------------------------------------------------------------------
  FOREST = {
    "backdrop" => "Forest",
    "outdoor" => false,
    "lightsC" => true,
    "img001" => {
      :bitmap => "forestShade", :z => 1, :flat => true,
      :oy => 0, :y => 94, :sheet => true, :frames => 2, :speed => 16
    },
    "img002" => { :bitmap => "cluster", :x => 10,  :y => 108, :z => 0, :opacity => 180 },
    "img003" => { :bitmap => "cluster", :x => 330, :y => 112, :z => 0, :opacity => 150, :mirror => true },
    "trees" => {
      :bitmap => "treePine", :colorize => false, :elements => 8,
      :x => [92, 248, 300, 40, 138, 216, 274, 318],
      :y => [132, 132, 144, 118, 112, 118, 110, 110],
      :zoom => [1, 1, 1.1, 0.9, 0.8, 0.85, 0.75, 0.75],
      :z => [2, 2, 2, 1, 1, 1, 1, 1]
    }
  }
  #-----------------------------------------------------------------------------
  # Simple field (fallback for missing graphics)
  #-----------------------------------------------------------------------------
  FIELD = {
    "backdrop" => "Field",
    "outdoor" => true
  }
  #-----------------------------------------------------------------------------
  # Sand environment — sandstorm dust using decor006 (panorama strip, same as cave smoke)
  #-----------------------------------------------------------------------------
  SAND = {
    "backdrop" => "Sand",
    "sky"      => true,
    "outdoor"  => true,
    "img001"   => { :bitmap => "mountainC", :x => 300, :y => 107 },
    "img002"   => {
      :bitmap => "decor006", :scrolling => true, :speed => 1.5, :direction => 1,
      :oy => 0, :z => 3, :flat => true, :opacity => 110
    },
    "img003"   => {
      :bitmap => "fog", :scrolling => true, :speed => 0.5, :direction => -1,
      :oy => 0, :z => 3, :flat => true, :opacity => 60
    }
  }
  #-----------------------------------------------------------------------------
  # Snow environment — blizzard haze using decor009 (pale mist panorama)
  #-----------------------------------------------------------------------------
  SNOW = {
    "backdrop"       => "Snow",
    "sky"            => true,
    "outdoor"        => true,
    "lightsC"        => true,
    "snowParticles"  => true,
    "img001"         => {
      :bitmap => "decor009", :scrolling => true, :speed => 2, :direction => -1,
      :oy => 0, :z => 3, :flat => true, :opacity => 170
    },
    "img002"         => {
      :bitmap => "fog", :scrolling => true, :speed => 0.5, :direction => 1,
      :oy => 0, :z => 4, :flat => true, :opacity => 90
    },
    "img003"         => { :bitmap => "mountainB", :x => 30,  :y => 90, :z => 0, :opacity => 160 },
    "img004"         => { :bitmap => "mountainB", :x => 270, :y => 95, :z => 0, :opacity => 130, :mirror => true },
  }
  #-----------------------------------------------------------------------------
  # Sky environment — high-altitude haze using fog panorama + lightsC sun rays
  #-----------------------------------------------------------------------------
  SKY = {
    "backdrop" => "Sky",
    "sky"      => true,
    "outdoor"  => true,
    "lightsC"  => true,
    "img001"   => {
      :bitmap => "decor009", :scrolling => true, :speed => 0.4, :direction => 1,
      :oy => 0, :z => 2, :flat => true, :opacity => 50
    },
    "img002"   => { :bitmap => "pillars001", :x => 70,  :y => 55, :z => 3 },
    "img003"   => { :bitmap => "pillars001", :x => 270, :y => 65, :z => 2, :mirror => true, :opacity => 180 },
    "img004"   => { :bitmap => "mountainB",  :x => 30,  :y => 118, :z => 1, :opacity => 90 },
    "img005"   => { :bitmap => "mountainB",  :x => 310, :y => 124, :z => 1, :opacity => 70, :mirror => true }
  }
  #-----------------------------------------------------------------------------
  # Underwater environment — murky water using decor009 + bubbles + seaweed
  #-----------------------------------------------------------------------------
  UNDERWATER = {
    "backdrop" => "Underwater",
    "water"    => true,
    "outdoor"  => false,
    "bubbles"  => true,
    "img001"   => {
      :bitmap => "seaWeed", :z => 2, :flat => true
    },
    "img002"   => {
      :bitmap => "decor009", :scrolling => true, :speed => 0.4, :direction => 1,
      :oy => 0, :z => 4, :flat => true, :opacity => 110
    },
    "img003"   => {
      :bitmap => "decor006", :scrolling => true, :speed => 0.2, :direction => -1,
      :oy => 0, :z => 4, :flat => true, :opacity => 60
    },
    "img004"   => {
      :bitmap => "skyNight", :scrolling => true, :speed => 0.1, :direction => 1,
      :oy => 0, :z => 1, :flat => true, :opacity => 80
    },
  }
  #-----------------------------------------------------------------------------
  # Puddle environment (water backdrop + puddle base)
  #-----------------------------------------------------------------------------
  PUDDLE = {
    "backdrop" => "Water",
    "base"     => "Puddle",
    "sky"      => true,
    "water"    => true,
    "outdoor"  => true
  }
end

#===============================================================================
#  Terrain additions
#===============================================================================
module TerrainEBDX
  MOUNTAIN = { "img001" => { :bitmap => "mountain", :x => 192, :y => 107 } }
  PUDDLE = { "base" => "Puddle" }
  DIRT = { "base" => "Dirt" }
  CONCRETE = { "base" => "Concrete" }
  WATER = { "base" => "Water", "water" => true }
  TALLGRASS = {
    "tallGrass" => {
      :elements => 7,
      :x => [124, 274, 204, 62, 248, 275, 182],
      :y => [160, 140, 140, 185, 246, 174, 170],
      :z => [2, 1, 2, 17, 27, 17, 17],
      :zoom => [0.7, 0.35, 0.5, 1, 1.5, 0.7, 1],
      :mirror => [false, true, false, true, false, true, false]
    }
  }
end
#===============================================================================
#  Register water environments and terrain tags with EBDX
#===============================================================================
EliteBattle.add_data(:MovingWater, :Environment, :BACKDROP, EnvironmentEBDX::WATER)
EliteBattle.add_data(:StillWater,  :Environment, :BACKDROP, EnvironmentEBDX::WATER)
EliteBattle.add_data(:Water,        :TerrainTag,  :BACKDROP, TerrainEBDX::WATER)
EliteBattle.add_data(:DeepWater,    :TerrainTag,  :BACKDROP, TerrainEBDX::WATER)
EliteBattle.add_data(:WaterCurrent, :TerrainTag,  :BACKDROP, TerrainEBDX::WATER)
EliteBattle.add_data(:StillWater,   :TerrainTag,  :BACKDROP, TerrainEBDX::WATER)
EliteBattle.add_data(:Waterfall,    :TerrainTag,  :BACKDROP, TerrainEBDX::WATER)
