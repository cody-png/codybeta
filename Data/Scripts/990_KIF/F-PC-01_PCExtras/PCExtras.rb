#===============================================================================
# F-PC-01 – PC extras: sort a box / all boxes, sort lock, Buy Box, wallpapers
# Source: KIF 0.20.7 (Reïzod, Sylvi)
#   016_UI/017_UI_PokemonStorage.rb:4572-4780  sort_box / sort_boxes /
#     pre_sort_boxes (25 criteria, Normal / Reverse order)
#   :4783-4870 box menu (Lock Sorting, Buy Box, Sort, Sort (all Boxes))
#   :784-830   "S" / "E" lock letters before the box name
#   :1785-1795 pbToggleSortBox / pbToggleExportBox
#   014_Pokemon/001_Pokemon-related/004_PokemonStorage.rb:5-36 (sortlock,
#     exportlock), :129-190 (160 extra wallpapers, always available)
#   Graphics/Pictures/Storage/box_40..199.png
#
# Box menu (6.8.2's "What do you want to do?" on the box name), after Name:
#   Lock/Unlock Sorting – "Sort (all Boxes)" leaves this box alone.
#   Lock/Unlock Exporting – used by Export All (F-PC-02).
#   Buy Box  – adds a box for P300 x number of boxes (max P100,000; free with
#              Streamer's Dream).
#   Sort / Sort (all Boxes) – by Name, Nickname, Dex Number, Level, HP, Atk,
#              Def, SpA, SpD, Spe, Caught Date, Shiny, OT, Gender, Ability,
#              Nature, Held Item, 1st Type, 2nd Type, Caught Map, Happiness,
#              EXP, Markings, Total IVs, Total EVs; Normal or Reverse order.
#              Sorted Pokémon are packed from the first slot (first unlocked
#              box for Sort all).
# Every box name shows a green (unlocked) or red (locked) "S" and "E".
# Wallpaper: KIF's 160 extra wallpapers are listed after 6.8.2's.
#
# 6.8.2 adaptations:
#   * 6.8.2 already has multi-select and "sort selected" (its own criteria);
#     both are kept. KIF's Battle / Export / Import entries come with F-PC-02
#     and F-PC-03.
#   * KIF numbered its wallpapers 40-199, but 6.8.2 uses 40-83 for its own
#     unlockable ones, so KIF's are numbered 1040-1199 (KIF number + 1000) and
#     load from Graphics/Pictures/KIF/Wallpapers/box_<n>.png. A vanilla PIF
#     load shows a basic wallpaper for those boxes instead.
#   * The Hoenn transfer box is never sorted or locked, and a bought box is
#     inserted before it.
#   * Ties keep their old order (KIF's order for equal values was random),
#     and empty values (no item, no map) sort as 0 instead of crashing.
#===============================================================================
class PokemonBox
  attr_writer :sortlock, :exportlock

  def sortlock?;   return !!@sortlock;   end
  def exportlock?; return !!@exportlock; end
  def sortlock;    return !!@sortlock;   end
  def exportlock;  return !!@exportlock; end
end

#-------------------------------------------------------------------------------
# Wallpapers
#-------------------------------------------------------------------------------
module KIF
  module Wallpapers
    BASE = 1000
    FIRST = 1040
    FOLDER = "Graphics/Pictures/KIF/Wallpapers/box_"

    def self.names
      return [
      _INTL("Fire Light"), _INTL("Fire Dark"), _INTL("Water Light"), _INTL("Water Dark"), _INTL("Grass Light"),   # 1040-1044
      _INTL("Grass Dark"), _INTL("Electric Light"), _INTL("Electric Dark"), _INTL("Ground Light"), _INTL("Ground Dark"),   # 1045-1049
      _INTL("Flying Light"), _INTL("Flying Dark"), _INTL("Psychic Light"), _INTL("Psychic Dark"), _INTL("Dark Light"),   # 1050-1054
      _INTL("Dark Dark"), _INTL("Fighting Light"), _INTL("Fighting Dark"), _INTL("Rock Light"), _INTL("Rock Dark"),   # 1055-1059
      _INTL("Steel Light"), _INTL("Steel Dark"), _INTL("Ghost Light"), _INTL("Ghost Dark"), _INTL("Bug Light"),   # 1060-1064
      _INTL("Bug Dark"), _INTL("Dragon Light"), _INTL("Dragon Dark"), _INTL("Fairy Light"), _INTL("Fairy Dark"),   # 1065-1069
      _INTL("Ice Light"), _INTL("Ice Dark"), _INTL("Poison Light"), _INTL("Poison Dark"), _INTL("Normal Light"),   # 1070-1074
      _INTL("Normal Dark"), _INTL("PMD Sand"), _INTL("PMD Snow"), _INTL("PMD Altar"), _INTL("PMD Trees"),   # 1075-1079
      _INTL("PMD Sharpedo Bluff"), _INTL("PMD Altar 2"), _INTL("PMD Time Stop"), _INTL("PMD Waterfall"), _INTL("PMD Time Tower"),   # 1080-1084
      _INTL("PMD Time Tower 2"), _INTL("PMD Guild"), _INTL("PMD Time Stop 2"), _INTL("PMD Sky"), _INTL("PMD Friends Space"),   # 1085-1089
      _INTL("PMD Friends Space 2"), _INTL("PMD Primal"), _INTL("PMD Tower"), _INTL("PMD Evolution"), _INTL("PMD Fire"),   # 1090-1094
      _INTL("PMD Mystery"), _INTL("PMD Night"), _INTL("PMD Cliff"), _INTL("PMD Worldview"), _INTL("Snowy"),   # 1095-1099
      _INTL("Poison"), _INTL("Dark Rural"), _INTL("Marathon"), _INTL("Gothic"), _INTL("Black Gradient"),   # 1100-1104
      _INTL("Yveltal"), _INTL("Plain Light"), _INTL("Plain Dark"), _INTL("Beach Sand"), _INTL("Blue Gradient"),   # 1105-1109
      _INTL("Night"), _INTL("Trade"), _INTL("Arid"), _INTL("City Path"), _INTL("Book"),   # 1110-1114
      _INTL("Cobwebs"), _INTL("Mt. Coronet"), _INTL("Altar"), _INTL("Slowpoke Well"), _INTL("Tin Tower"),   # 1115-1119
      _INTL("Search Light"), _INTL("Search Dark"), _INTL("Mewtwo Lab"), _INTL("Team Rocket 1"), _INTL("Team Rocket 2"),   # 1120-1124
      _INTL("Team Flare"), _INTL("Coral"), _INTL("Training"), _INTL("Dream Space"), _INTL("School"),   # 1125-1129
      _INTL("Underwater"), _INTL("Underwater 2"), _INTL("Chess"), _INTL("Rainbow Plain"), _INTL("Mushrooms"),   # 1130-1134
      _INTL("Plain Pathway"), _INTL("Mountain"), _INTL("Shiny Blue"), _INTL("Shiny Red"), _INTL("Shiny Green"),   # 1135-1139
      _INTL("Shiny Purple"), _INTL("Minecraft Rails"), _INTL("Minecraft Rails 2"), _INTL("Infernal"), _INTL("Insectoid"),   # 1140-1144
      _INTL("Halloween"), _INTL("Neon"), _INTL("Obscuros"), _INTL("Japan"), _INTL("Norse"),   # 1145-1149
      _INTL("Oblivion"), _INTL("Rainbow"), _INTL("River"), _INTL("Sunset"), _INTL("Shadow"),   # 1150-1154
      _INTL("Soulfire"), _INTL("Temple"), _INTL("Sweet Shop"), _INTL("Anubis"), _INTL("Dark"),   # 1155-1159
      _INTL("Demonic"), _INTL("Ethereal"), _INTL("Forest"), _INTL("Gembound"), _INTL("Snow Game"),   # 1160-1164
      _INTL("Mega Evolution"), _INTL("Golden Night"), _INTL("Milotic Style"), _INTL("X & Y"), _INTL("Steampunk"),   # 1165-1169
      _INTL("Synthwave Neon"), _INTL("Xerneas"), _INTL("Charged Steel"), _INTL("Reshiram & Zekrom"), _INTL("Kyurems"),   # 1170-1174
      _INTL("Beautiful Underwater"), _INTL("Synthwave Sunset"), _INTL("Team Magma"), _INTL("Team Aqua"), _INTL("Victini"),   # 1175-1179
      _INTL("Weezing/Kyogre"), _INTL("Star Snow"), _INTL("Dark Graphs"), _INTL("Purple Geometry"), _INTL("RGBY Squares"),   # 1180-1184
      _INTL("RIP"), _INTL("RIP 2"), _INTL("Pizza"), _INTL("Fusing Chart"), _INTL("Roaring Reshigon"),   # 1185-1189
      _INTL("Arcade Academy"), _INTL("Windows XP"), _INTL("Doggy XP"), _INTL("Mewtwo Strikes"), _INTL("Pikachu Sad"),   # 1190-1194
      _INTL("Ash Ded"), _INTL("Shadow Lugia"), _INTL("Primal Dialga"), _INTL("Bluescreen"), _INTL("Bluescreen 2"),   # 1195-1199
      ]
    end

    def self.kif?(id)
      return id.is_a?(Integer) && id >= FIRST && id < FIRST + names.length
    end

    def self.path(id)
      return FOLDER + id.to_s
    end
  end
end

class PokemonStorage
  alias kif_wp_isAvailableWallpaper? isAvailableWallpaper? unless method_defined?(:kif_wp_isAvailableWallpaper?)
  alias kif_wp_availableWallpapers availableWallpapers unless method_defined?(:kif_wp_availableWallpapers)

  def isAvailableWallpaper?(i)
    return true if KIF::Wallpapers.kif?(i)
    return kif_wp_isAvailableWallpaper?(i)
  end

  def availableWallpapers
    ret = kif_wp_availableWallpapers
    KIF::Wallpapers.names.each_with_index do |name, k|
      ret[0].push(name)
      ret[1].push(KIF::Wallpapers::FIRST + k)
    end
    return ret
  end
end

class PokemonBoxSprite
  alias kif_wp_getBoxBitmap getBoxBitmap unless method_defined?(:kif_wp_getBoxBitmap)
  alias kif_pc_refresh refresh unless method_defined?(:kif_pc_refresh)

  def getBoxBitmap
    bg = @storage[@boxnumber].background
    if KIF::Wallpapers.kif?(bg) && pbResolveBitmap(KIF::Wallpapers.path(bg))
      return if @bg == bg && @boxbitmap
      @bg = bg
      @boxbitmap.dispose if @boxbitmap
      @boxbitmap = AnimatedBitmap.new(KIF::Wallpapers.path(bg))
      return
    end
    return kif_wp_getBoxBitmap
  end

  # KIF: green/red "S" (sort lock) and "E" (export lock) before the name
  def refresh
    redraw = @refreshBox
    kif_pc_refresh
    return unless redraw
    box = @storage[@boxnumber]
    return if box.nil? || box.is_a?(StorageTransferBox) || !@boxbitmap
    @contents.blt(0, 0, @boxbitmap.bitmap, Rect.new(0, 0, 324, 40))
    pbSetSystemFont(@contents)
    boxname = box.name
    widthval = @contents.text_size(boxname).width
    xval = 162 - ((widthval + 32) / 2)
    shadow = Color.new(40, 48, 48)
    color = box.sortlock? ? Color.new(200, 15, 15) : Color.new(0, 200, 0)
    pbDrawShadowText(@contents, xval, 8, 32, 32, "S", color, shadow)
    xval += 16
    color = box.exportlock? ? Color.new(200, 15, 15) : Color.new(0, 200, 0)
    pbDrawShadowText(@contents, xval, 8, 32, 32, "E", color, shadow)
    xval += 16
    pbDrawShadowText(@contents, xval, 8, widthval, 32, boxname, Color.new(248, 248, 248), shadow)
  rescue => e
    KIF.log("Box header failed: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# Sorting
#-------------------------------------------------------------------------------
module KIF
  module BoxSort
    # Labels are translated when shown
    CRITERIA = [
      ["Sort by Name", :speciesName], ["Sort by Nickname", :name],
      ["Sort by Dex Number", :dexNum], ["Sort by Level", :level],
      ["Sort by HP", :totalhp], ["Sort by Atk", :attack],
      ["Sort by Def", :defense], ["Sort by SpA", :spatk],
      ["Sort by SpD", :spdef], ["Sort by Spe", :speed],
      ["Sort by Caught Date", :timeReceived], ["Sort by Shiny", :shiny],
      ["Sort by OT", :OT], ["Sort by Gender", :gender],
      ["Sort by Ability", :ability], ["Sort by Nature", :nature],
      ["Sort by Held Item", :item], ["Sort by 1st Type", :type1],
      ["Sort by 2nd Type", :type2], ["Sort by Caught Map", :obtain_map],
      ["Sort by Happiness", :happiness], ["Sort by EXP", :exp],
      ["Sort by Markings", :markings], ["Sort by Total IVs", :totalivs],
      ["Sort by Total EVs", :totalevs]
    ]

    # KIF sort_box values
    def self.value(p, attr)
      ret = case attr
            when :shiny    then p.shiny? ? 1 : 0
            when :OT       then (p.owner && !p.owner.name.to_s.empty?) ? p.owner.name : "0"
            when :gender   then (p.respond_to?(:pizza?) && p.pizza?) ? 3 : p.gender
            when :ability  then p.ability ? p.ability.name : ""
            when :nature   then p.nature ? p.nature.name : ""
            when :item     then p.item ? p.item.name : "0"
            when :type1    then GameData::Type.get(p.type1).id_number
            when :type2    then GameData::Type.get(p.type2).id_number
            when :totalivs then p.iv.values.sum
            when :totalevs then p.ev.values.sum
            else p.send(attr)
            end
      return ret.nil? ? 0 : ret
    rescue
      return 0
    end

    def self.compare(a, b)
      c = (a[0] <=> b[0])
      c = (a[0].to_s <=> b[0].to_s) if c.nil?
      return (c == 0) ? (a[1] <=> b[1]) : c
    end

    # Sorted list of Pokémon (nil-free) or nil if cancelled
    def self.ask_and_sort(screen, pokes)
      labels = CRITERIA.map { |l, _| _INTL(l) } + [_INTL("Nevermind")]
      cmd = screen.pbShowCommands(_INTL("Sort box how ?"), labels)
      return nil if cmd < 0 || cmd >= CRITERIA.length
      return nil if pokes.empty?
      attr = CRITERIA[cmd][1]
      order = screen.pbShowCommands(_INTL("Sort box how ?"),
                                    [_INTL("Normal Order"), _INTL("Reverse Order"), _INTL("Nevermind")])
      return nil if order < 0 || order > 1
      pairs = pokes.each_with_index.map { |p, i| [value(p, attr), i] }
      pairs.sort! { |a, b| compare(a, b) }
      pairs.reverse! if order == 1
      return pairs.map { |_, i| pokes[i] }
    end

    def self.sortable_boxes(storage)
      return (0...storage.maxBoxes).select do |j|
        box = storage[j]
        !box.is_a?(StorageTransferBox) && !box.sortlock?
      end
    end

    def self.sort(screen, all)
      storage = screen.storage
      boxes = all ? sortable_boxes(storage) : [storage.currentBox]
      pokes = []
      boxes.each { |j| storage.maxPokemon(j).times { |k| pokes << storage[j, k] if storage[j, k] } }
      sorted = ask_and_sort(screen, pokes)
      return unless sorted
      boxes.each { |j| storage.maxPokemon(j).times { |k| storage[j, k] = nil } }
      i = 0
      boxes.each do |j|
        storage.maxPokemon(j).times do |k|
          break if i >= sorted.length
          storage[j, k] = sorted[i]
          i += 1
        end
      end
      screen.pbHardRefresh
      screen.pbDisplay(_INTL("Pokemons sorted!"))
    end

    def self.buy_box(screen)
      storage = screen.storage
      normal = storage.boxes.count { |b| !b.is_a?(StorageTransferBox) }
      price = [normal * 300, 100000].min
      price = KIF::PCActions.price(price)
      if $Trainer.money < price
        pbPlayBuzzerSE
        screen.pbDisplay(_INTL("Not enough Money ! Cost P{1}", price.to_s_formatted))
        return
      end
      cmd = screen.pbShowCommands(_INTL("You have P{1}", $Trainer.money.to_s_formatted),
                                  [_INTL("Buy! (P{1})", price.to_s_formatted), _INTL("Nevermind")])
      return if cmd != 0
      $Trainer.money -= price
      pos = storage.boxes.index { |b| b.is_a?(StorageTransferBox) } || storage.boxes.length
      storage.boxes.insert(pos, PokemonBox.new(_INTL("Box {1}", pos + 1), PokemonBox::BOX_SIZE))
      screen.pbDisplay(_INTL("Bought a new box!"))
    end

    def self.toggle(screen, flag)
      box = screen.storage[screen.storage.currentBox]
      if flag == :sort
        box.sortlock = !box.sortlock?
      else
        box.exportlock = !box.exportlock?
      end
      screen.pbHardRefresh
    end
  end
end

KIF::BoxCommands.add(:sortlock,
  proc { |s| s.storage[s.storage.currentBox].sortlock? ? _INTL("Unlock Sorting") : _INTL("Lock Sorting") },
  proc { |s| KIF::BoxSort.toggle(s, :sort) }, order: 10)
KIF::BoxCommands.add(:exportlock,
  proc { |s| s.storage[s.storage.currentBox].exportlock? ? _INTL("Unlock Exporting") : _INTL("Lock Exporting") },
  proc { |s| KIF::BoxSort.toggle(s, :export) }, order: 20)
KIF::BoxCommands.add(:buybox, proc { |_s| _INTL("Buy Box") },
  proc { |s| KIF::BoxSort.buy_box(s) }, order: 30)
KIF::BoxCommands.add(:sort, proc { |_s| _INTL("Sort") },
  proc { |s| KIF::BoxSort.sort(s, false) }, order: 40)
KIF::BoxCommands.add(:sortall, proc { |_s| _INTL("Sort (all Boxes)") },
  proc { |s| KIF::BoxSort.sort(s, true) }, order: 50)
