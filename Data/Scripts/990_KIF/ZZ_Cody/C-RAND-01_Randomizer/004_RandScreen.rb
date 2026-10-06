#===============================================================================
# C-RAND-01 – the Randomizer screen (replaces PIF's RandomizerOptionsScene,
# which PIF's events open when a randomized save is made). Also reachable from
# Cody Settings on saves started as randomized saves. Built from the game's
# own option windows, so it follows the player's frame and dark mode.
#===============================================================================
module KIF
  module Rand
    # Button whose name is worked out when drawn ("Pokémon (On)")
    class DynButton < ButtonOption
      def initialize(name_proc, press, description = "")
        super("", press, description)
        @name_proc = name_proc
      end

      def name
        return @name_proc.call
      end
    end

    def self.on_off(on)
      return on ? _INTL("On") : _INTL("Off")
    end

    def self.page_state(page)
      case page
      when :pokemon then return on_off(pokemon_parts_on?)
      when :trainers then return on_off(get(:trainers) > 0)
      when :gyms then return on_off(get(:gyms) == 1)
      when :items then return on_off(sw(SWITCH_RANDOM_ITEMS_GENERAL))
      when :data then return on_off(dget(:types) > 0 || dget(:moves_follow) == 1 || dget(:tms_follow) == 1 || dget(:abilities) > 0 || dget(:stats) > 0)
      when :evolutions then return on_off(dget(:evolutions) > 0)
      when :exclusions then return (bans(:pokemon).length + bans(:moves).length + bans(:abilities).length).to_s
      end
      return ""
    end

    def self.enum(key, name, values, descs)
      return EnumOption.new(name, values,
                            proc { KIF::Rand.get(key) },
                            proc { |v| KIF::Rand.set(key, v) }, descs)
    end

    def self.onoff(key, name, desc_off, desc_on)
      return enum(key, name, [_INTL("Off"), _INTL("On")], [desc_off, desc_on])
    end

    # 3-digit number (each digit 0-9) instead of a slider (Cody)
    def self.slider(key, name, desc)
      return DynButton.new(proc { sprintf("%s: %03d", name, KIF::Rand.get(key)) },
                           proc {
                             params = ChooseNumberParams.new
                             params.setRange(0, 999)
                             params.setMaxDigits(3)
                             params.setInitialValue(KIF::Rand.get(key))
                             params.setCancelValue(KIF::Rand.get(key))
                             KIF::Rand.digit_wrap = true
                             begin
                               v = pbMessageChooseNumber(_INTL("{1} (0-999)? Up/Down: digit, Left/Right: move.", name), params)
                             ensure
                               KIF::Rand.digit_wrap = false
                             end
                             KIF::Rand.set(key, v)
                           }, desc)
    end

    def self.open_page(title, desc, color, &builder)
      pbFadeOutIn {
        scene = KifRandPageScene.new(title, desc, color, builder)
        PokemonOptionScreen.new(scene).pbStartScreen
      }
    end

    GREEN = [Color.new(70, 170, 40), Color.new(40, 100, 20)]

    def self.page_pokemon
      open_page(_INTL("Randomizer: Pokémon"), _INTL("Which Pokémon are randomized, and how."), GREEN) {
        [
          enum(:wild_mode, _INTL("Wild encounters"),
               [_INTL("Off"), _INTL("Swap"), _INTL("Route"), _INTL("Dynamic")],
               [_INTL("Wild Pokémon are not randomized."),
                _INTL("Each species becomes one other species everywhere."),
                _INTL("Every route rolls its own Pokémon."),
                _INTL("Every encounter is any Pokémon, rolled on the spot.")]),
          enum(:starters, _INTL("Starters"), [_INTL("Off"), _INTL("1st"), _INTL("Any")],
               [_INTL("The starters are not randomized."),
                _INTL("The starters are random first-stage Pokémon."),
                _INTL("The starters can be any Pokémon.")]),
          onoff(:statics, _INTL("Static encounters"),
                _INTL("Overworld Pokémon (legendaries included) are not randomized."),
                _INTL("Overworld Pokémon (legendaries included) are randomized.")),
          onoff(:gifts, _INTL("Gift Pokémon"),
                _INTL("Pokémon given to you are not randomized."),
                _INTL("Pokémon given to you are randomized.")),
          onoff(:trades, _INTL("Trades"),
                _INTL("Pokémon from in-game trades are not randomized."),
                _INTL("Pokémon from in-game trades are randomized.")),
          slider(:wild_bst, _INTL("Strength range"),
                 _INTL("How close in base stat total a replacement must be. 999 = anything.")),
          onoff(:wild_legend, _INTL("Legendaries"),
                _INTL("Only legendaries become legendaries."),
                _INTL("Any Pokémon can become a legendary.")),
          onoff(:wild_custom, _INTL("Custom sprites only"),
                _INTL("Fusions can use auto-generated sprites."),
                _INTL("Fusions only use ones with a custom sprite.")),
          onoff(:fuse_all, _INTL("Fuse everything"),
                _INTL("Wild Pokémon can be unfused."),
                _INTL("All wild Pokémon are already fused."))
        ]
      }
    end

    def self.page_trainers
      open_page(_INTL("Randomizer: Trainers"), _INTL("Trainer teams."), nil) {
        [
          enum(:trainers, _INTL("Trainers"), [_INTL("Off"), _INTL("Random"), _INTL("Follow wild")],
               [_INTL("Trainer teams are not randomized."),
                _INTL("Every trainer's Pokémon are rolled on their own."),
                _INTL("Trainer Pokémon follow the wild swap table: a trainer's Pidgey becomes whatever wild Pidgey became.")]),
          slider(:trainer_bst, _INTL("Strength range"),
                 _INTL("How close in base stat total a replacement must be. 999 = anything.")),
          onoff(:trainer_custom, _INTL("Custom sprites only"),
                _INTL("Trainer teams can use auto-generated sprites."),
                _INTL("Trainer teams only use Pokémon with a custom sprite.")),
          onoff(:class_themes, _INTL("Class themes"),
                _INTL("Trainer classes can use any type."),
                _INTL("Every Pokémon of a themed class has its type: Bug Catchers use Bug types, Swimmers Water types, ...")),
          onoff(:theme_shuffle, _INTL("Shuffle themes"),
                _INTL("Classes keep their usual type (needs Class themes On)."),
                _INTL("Each class gets a random type instead, e.g. Bug Catchers using Fire types. Type Experts keep theirs.")),
          onoff(:rival_team, _INTL("Rival keeps his team"),
                _INTL("The rival's team is rolled again for each battle."),
                _INTL("Each Pokémon in the rival's team gets one replacement for every battle, evolving as his team does.")),
          enum(:team_size, _INTL("Team size"), [_INTL("Same"), _INTL("+1"), _INTL("+2"), _INTL("Full")],
               [_INTL("Trainers keep their usual number of Pokémon."),
                _INTL("Trainers get 1 more Pokémon (up to 6), at the team's average level."),
                _INTL("Trainers get 2 more Pokémon (up to 6), at the team's average level."),
                _INTL("Every trainer has 6 Pokémon. The extras join at the team's average level.")]),
          onoff(:trainer_fuse, _INTL("Fuse everything"),
                _INTL("Trainer Pokémon can be unfused."),
                _INTL("Every trainer Pokémon is a fusion.")),
          ButtonOption.new(_INTL("Class theme list"), proc {
            KIF::Rand.show_lines(_INTL("Class themes"), KIF::Rand.class_theme_lines)
          }, _INTL("Which type each trainer class uses. Gym leaders use the Gyms page."))
        ]
      }
    end

    def self.page_gyms
      open_page(_INTL("Randomizer: Gyms"), _INTL("Gym trainers and leaders (needs Trainers on)."), nil) {
        [
          onoff(:gyms, _INTL("Gym trainers"),
                _INTL("Gym teams are randomized like other trainers."),
                _INTL("Gym teams stick to the gym's type.")),
          onoff(:gym_custom, _INTL("Custom sprites only"),
                _INTL("Gym teams can use auto-generated sprites."),
                _INTL("Gym teams only use Pokémon with a custom sprite.")),
          onoff(:gym_types, _INTL("Gym types"),
                _INTL("Gyms keep their usual types."),
                _INTL("Gym types are shuffled.")),
          onoff(:gym_each, _INTL("Rerandomize each battle"),
                _INTL("Gym teams stay the same each try."),
                _INTL("Gym teams change on every try."))
        ]
      }
    end

    def self.page_items
      open_page(_INTL("Randomizer: Items"), _INTL("Items and TMs."), nil) {
        [
          onoff(:found_items, _INTL("Found items"), _INTL("Items on the ground are normal."), _INTL("Items on the ground are randomized.")),
          onoff(:found_tms, _INTL("Found TMs"), _INTL("TMs on the ground are normal."), _INTL("TMs on the ground are randomized.")),
          onoff(:given_items, _INTL("Given items"), _INTL("Items from NPCs are normal."), _INTL("Items from NPCs are randomized (may break some quests).")),
          onoff(:given_tms, _INTL("Given TMs"), _INTL("TMs from NPCs are normal."), _INTL("TMs from NPCs are randomized.")),
          onoff(:shop_items, _INTL("Shop items"), _INTL("Shops sell their usual items."), _INTL("Shop stock is randomized.")),
          onoff(:held_items, _INTL("Trainer held items"), _INTL("Trainers hold their usual items."), _INTL("Trainers hold random items."))
        ]
      }
    end

    def self.page_data
      open_page(_INTL("Randomizer: Pokémon data"), _INTL("Types, moves, abilities and base stats. Fusions follow."), GREEN) {
        [
          enum(:types, _INTL("Types"), [_INTL("Same"), _INTL("Random"), _INTL("Dual")],
               [_INTL("Types stay the same."),
                _INTL("Each evolution family gets new types."),
                _INTL("New types, and every Pokémon gets two.")]),
          enum(:type_orig, _INTL("Original type"), [_INTL("Allowed"), _INTL("Never")],
               [_INTL("A Pokémon may roll its own type again."),
                _INTL("A Pokémon never keeps its original types.")]),
          onoff(:moves_follow, _INTL("Moves follow type"),
                _INTL("Level-up and egg moves stay the same."),
                _INTL("Moves of the old type become the new type's, same level, similar power.")),
          onoff(:tms_follow, _INTL("TMs follow type"),
                _INTL("TM and tutor compatibility stays the same."),
                _INTL("TM/tutor moves of the old type become the new type's.")),
          enum(:abilities, _INTL("Abilities"), [_INTL("Same"), _INTL("Random"), _INTL("Flavour"), _INTL("Bound")],
               [_INTL("Abilities stay the same."),
                _INTL("Any ability."),
                _INTL("Type-flavoured: abilities themed on the Pokémon's types."),
                _INTL("Type-bound: only abilities Pokémon of its types have in the base game.")]),
          onoff(:no_selfharm, _INTL("No self-harm"),
                _INTL("Any ability can be picked."),
                _INTL("Never Truant, Slow Start, Defeatist, Klutz, Stall or weather that hurts its own type.")),
          enum(:stats, _INTL("Base stats"), [_INTL("Same"), _INTL("Shuffle"), _INTL("Total"), _INTL("Chaos")],
               [_INTL("Base stats stay the same."),
                _INTL("Same numbers in a new order (the same order for the whole family)."),
                _INTL("Random spread with the same total."),
                _INTL("Every stat rolled from 1 to 255.")]),
          enum(:chaos_safety, _INTL("Chaos safety"), [_INTL("Off"), _INTL("Total"), _INTL("Each stat")],
               [_INTL("Chaos: an evolution can be weaker."),
                _INTL("Chaos: evolving never lowers the base stat total."),
                _INTL("Chaos: evolving never lowers any stat.")])
        ]
      }
    end

    def self.page_evolutions
      open_page(_INTL("Randomizer: Evolutions"), _INTL("Evolves into a higher stage or a Final. Levels and items stay the same."), GREEN) {
        [
          enum(:evolutions, _INTL("Evolutions"), [_INTL("Same"), _INTL("Random")],
               [_INTL("Evolutions stay the same."),
                _INTL("Evolves into a higher stage or a Final. Levels and items stay the same.")]),
          onoff(:evo_typed, _INTL("Type-themed"),
                _INTL("The evolution can be any type."),
                _INTL("The evolution shares a type with the Pokémon."))
        ]
      }
    end

    def self.page_exclusions
      open_page(_INTL("Randomizer: Exclusions"), _INTL("Pokémon, moves and abilities the randomizer never picks."), nil) {
        [[:pokemon, _INTL("Banned Pokémon")], [:moves, _INTL("Banned moves")], [:abilities, _INTL("Banned abilities")]].map do |kind, label|
          DynButton.new(proc { "#{label} (#{KIF::Rand.bans(kind).length})" },
                        proc { KIF::Rand.ban_picker(kind, label) },
                        _INTL("A: ban / unban   L/R: page   Z: clear all"))
        end
      }
    end

    def self.ban_entries(kind)
      @ban_entries ||= {}
      @ban_entries[kind] ||= case kind
        when :pokemon then base_species.map { |sp| [sp.species, sprintf("%03d %s", sp.id_number, sp.real_name)] }
        when :moves then move_pool.map { |m| [m.id, m.real_name] }.sort_by { |x| x[1] }
        else all_abilities.map { |a| [a, GameData::Ability.get(a).real_name] }.sort_by { |x| x[1] }
      end
    end

    # A: ban/unban, L/R: page, Z (Action): clear all, B: back
    def self.ban_picker(kind, label)
      entries = ban_entries(kind)
      list = bans(kind)
      rows = proc { entries.map { |id, name| list.include?(id) ? "#{name}  [banned]" : name } }
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 999999
      head = Window_UnformattedTextPokemon.newWithSize(label, 0, 0, Graphics.width, 64, vp)
      win = Window_CommandPokemon.newWithSize(rows.call, 0, 64, Graphics.width, Graphics.height - 64, vp)
      win.index = 0
      loop do
        Graphics.update
        Input.update
        win.update
        if Input.trigger?(Input::USE)
          id = entries[win.index][0]
          list.include?(id) ? list.delete(id) : list << id
          pbPlayDecisionSE
          i = win.index
          win.commands = rows.call
          win.index = i
        elsif Input.trigger?(Input::ACTION)
          if !list.empty? && pbConfirmMessage(_INTL("Unban everything in this list?"))
            list.clear
            win.commands = rows.call
          end
        elsif Input.repeat?(Input::JUMPUP)
          win.index = [win.index - 10, 0].max
        elsif Input.repeat?(Input::JUMPDOWN)
          win.index = [win.index + 10, entries.length - 1].min
        elsif Input.trigger?(Input::BACK)
          pbPlayCancelSE
          break
        end
      end
      win.dispose
      head.dispose
      vp.dispose
      eat_input
    end

    # The page behind checks the same frame's Back press; one more input update
    # makes sure closing a list doesn't close that page too
    def self.eat_input
      Graphics.update
      Input.update
    end

    #---------------------------------------------------------------------------
    def self.seed_menu
      cmds = [_INTL("New random seed"), _INTL("Type a seed"), _INTL("Copy seed"), _INTL("Cancel")]
      case pbMessage(_INTL("Seed: {1}", format_seed), cmds, cmds.length)
      when 0
        self.seed = new_seed
        pbMessage(_INTL("New seed: {1}", format_seed))
      when 1
        text = pbMessageFreeText(_INTL("Seed (8 letters/numbers):"), format_seed, false, 9)
        s = parse_seed(text)
        if s
          self.seed = s
        elsif text && !text.strip.empty?
          pbMessage(_INTL("A seed is 8 letters and numbers (no I, O, 0 or 1)."))
        end
      when 2
        Input.clipboard = format_seed rescue nil
        pbMessage(_INTL("Seed copied."))
      end
    end

    def self.page_presets
      open_page(_INTL("Presets & sharing"), _INTL("Share or keep your randomizer settings."), nil) {
        [
          ButtonOption.new(_INTL("Copy settings code"), proc {
            begin
              Input.clipboard = KIF::Rand.settings_code
              pbMessage(_INTL("Copied: {1}", KIF::Rand.settings_code))
            rescue
              pbMessage(_INTL("Couldn't copy. The code is: {1}", KIF::Rand.settings_code))
            end
          }, _INTL("Copies the seed and every setting as one line.")),
          ButtonOption.new(_INTL("Paste settings code"), proc {
            text = (Input.clipboard rescue nil).to_s.strip
            res = KIF::Rand.parse_code(text)
            if !res
              pbMessage(_INTL("The clipboard doesn't hold a settings code (it starts with {1}).", KIF::Rand::CODE_PREFIX))
            elsif pbConfirmMessage(_INTL("Load these settings? Seed {1}.", KIF::Rand.format_seed(res[0])))
              KIF::Rand.apply_code(text)
              pbMessage(_INTL("Loaded. Use Randomize now for them to take effect."))
            end
          }, _INTL("Loads a settings code copied from someone else.")),
          ButtonOption.new(_INTL("Save as preset"), proc {
            name = pbMessageFreeText(_INTL("Preset name:"), "", false, 30)
            if name && !name.strip.empty?
              ok = KIF::Rand.save_preset(name)
              pbMessage(ok ? _INTL("Saved to the {1} folder.", KIF::Rand::PRESET_DIR) : _INTL("Couldn't save that preset."))
            end
          }, _INTL("Saves these settings as a file you can share.")),
          ButtonOption.new(_INTL("Load preset"), proc {
            names = KIF::Rand.preset_names
            if names.empty?
              pbMessage(_INTL("No presets yet. They're kept in the {1} folder.", KIF::Rand::PRESET_DIR))
            else
              i = pbMessage(_INTL("Which preset?"), names + [_INTL("Cancel")], names.length + 1)
              if i >= 0 && i < names.length
                ok = KIF::Rand.load_preset(names[i])
                pbMessage(ok ? _INTL("Loaded. Use Randomize now for it to take effect.") : _INTL("That preset couldn't be read."))
              end
            end
          }, _INTL("Loads a preset from the {1} folder.", KIF::Rand::PRESET_DIR))
        ]
      }
    end

    #---------------------------------------------------------------------------
    # Randomize now: the same steps as Common Event 28, on the seed
    #---------------------------------------------------------------------------
    def self.randomize_now
      sync_masters
      setsw(SWITCH_RANDOMIZED_AT_LEAST_ONCE, true)
      progress("Randomizing Pokémon data...", 0.2)
      if data_on?
        randomize_data
      else
        data[:species] = nil
        apply_data({})
      end
      Kernel.initRandomTypeArray
      if pokemon_parts_on?
        data[:dex_ok] = false
        Kernel.pbShuffleDex($game_variables[VAR_RANDOMIZER_WILD_POKE_BST])
        setsw(669, true)
        Kernel.randomizeWildPokemonByRoute if sw(SWITCH_RANDOM_WILD_AREA)
      end
      if sw(SWITCH_RANDOM_TRAINERS)
        sw(600) ? Kernel.pbShuffleTrainersCustom : Kernel.pbShuffleTrainers
        $PokemonGlobal.randomGymTrainersHash = {}
      end
      $PokemonGlobal.randomItemsHash = nil
      $PokemonGlobal.randomTMsHash = nil
      pbShuffleItems if sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_SHOP_ITEMS)
      pbShuffleTMs if sw(SWITCH_RANDOM_TMS)
      KIF::Rand.progress_done
      write_log
    end
  end
end

module KIF
  module Rand
    @digit_wrap = false
    class << self
      attr_accessor :digit_wrap
    end
  end
end

# Strength range picker: each digit wraps on its own (0 down -> 9, 9 up -> 0)
# without touching the other digits (PIF's number box carries/borrows).
# Only while the randomizer's picker is open.
class Window_InputNumberPokemon
  alias kif_rand_update update unless method_defined?(:kif_rand_update)

  def update
    return kif_rand_update unless KIF::Rand.digit_wrap && self.active
    return kif_rand_update unless Input.repeat?(Input::UP) || Input.repeat?(Input::DOWN)
    digits = @digits_max + (@sign ? 1 : 0)
    return kif_rand_update if @index == 0 && @sign
    SpriteWindow_Base.instance_method(:update).bind(self).call
    place = 10 ** (digits - 1 - @index)
    d = (@number / place) % 10
    nd = Input.repeat?(Input::UP) ? (d + 1) % 10 : (d + 9) % 10
    @number += (nd - d) * place
    pbPlayCursorSE
    refresh
    @frame = (@frame + 1) % 30
  end
end

# PIF's option list gives names 9/20 of the width and squeezes longer names
# (blurry text, e.g. "Paste settings code"). The randomizer's lists draw
# buttons across the whole row and give names 11/20 next to On/Off values.
class KifRandOptionWindow < Window_PokemonOption
  def drawItem(index, _count, rect)
    return super if index >= @options.length
    opt = @options[index]
    if opt.is_a?(ButtonOption)
      rect = drawCursor(index, rect)
      pbDrawShadowText(self.contents, rect.x, rect.y, rect.width, rect.height, opt.name,
                       @nameBaseColor, @nameShadowColor)
      return
    end
    return super unless opt.is_a?(EnumOption) && opt.values.length > 1
    rect = drawCursor(index, rect)
    namew = kif_name_width(rect.width)
    valw = rect.width - namew
    pbDrawShadowText(self.contents, rect.x, rect.y, namew, rect.height, opt.name,
                     @nameBaseColor, @nameShadowColor)
    widths = opt.values.map { |v| self.contents.text_size(v).width }
    gaps = opt.values.length - 1
    if widths.sum + gaps * 12 <= valw
      # Every value fits: spread them over the value column
      spacing = (valw - widths.sum) / gaps
      xpos = rect.x + namew
      opt.values.each_with_index do |v, i|
        sel = (i == self[index])
        pbDrawShadowText(self.contents, xpos, rect.y, widths[i] + 2, rect.height, v,
                         sel ? @selBaseColor : self.baseColor, sel ? @selShadowColor : self.shadowColor)
        xpos += widths[i] + spacing
      end
    else
      # Too many to fit: show the chosen one between arrows (Left/Right still cycle)
      v = opt.values[self[index]] || ""
      pbDrawShadowText(self.contents, rect.x + namew, rect.y, valw, rect.height,
                       "< #{v} >", @selBaseColor, @selShadowColor, 1)
    end
  end

  # The name column is as wide as the page's longest name (plus a gap), so
  # pages with short names leave more room for the values
  def kif_name_width(full)
    return @kif_namew if @kif_namew
    names = @options.select { |o| o.is_a?(EnumOption) }.map { |o| self.contents.text_size(o.name).width }
    w = (names.max || 0) + 20
    @kif_namew = [[w, full * 3 / 10].max, full * 11 / 20].min
    return @kif_namew
  end
end

#-------------------------------------------------------------------------------
# Description box: text too long for its two lines scrolls slowly downwards
# like a car radio display, then starts over (Cody)
#-------------------------------------------------------------------------------
module KifScrollText
  HOLD  = 1.5    # s shown still at the top and at the bottom
  SPEED = 24.0   # pixels per second (a line is 32)

  def self.now
    return Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def setText(value)
    super
    @kif_t0 = KifScrollText.now
    self.oy = 0
  end

  # The game's window only draws the lines that fit; this one draws all of
  # them so they can scroll into view
  def refresh
    return super if self.letterbyletter
    self.contents = pbDoEnsureBitmap(self.contents, [@bitmapwidth, 1].max, [@bitmapheight + 8, 1].max)
    self.contents.font = @oldfont if @oldfont
    self.contents.clear
    (@fmtchars || []).each { |ch| drawSingleFormattedChar(self.contents, ch) }
    self.contents.font = @oldfont if @oldfont
  end

  def kif_scroll_update
    return if self.disposed? || !self.contents
    # Only text with more lines than the box shows scrolls (a line is 32px;
    # the few pixels of padding under the last line don't count)
    over = (@bitmapheight || 0) - (self.height - self.borderY)
    if over <= 8
      self.oy = 0 if self.oy != 0
      return
    end
    @kif_t0 ||= KifScrollText.now
    move = over / SPEED
    t = (KifScrollText.now - @kif_t0) % (HOLD * 2 + move)
    y = (t < HOLD) ? 0 : [((t - HOLD) * SPEED).floor, over + 4].min
    self.oy = y if self.oy != y
  end
end

module KifRandWindowMixin
  def pbUpdate
    super
    tb = @sprites && @sprites["textbox"]
    tb.kif_scroll_update if tb.respond_to?(:kif_scroll_update)
  end

  def initOptionsWindow
    tb = @sprites["textbox"]
    if tb.is_a?(Window_AdvancedTextPokemon) && !tb.is_a?(KifScrollText)
      tb.extend(KifScrollText)
      tb.text = tb.text
    end
    width = Graphics.width
    height = (Graphics.height - @sprites["title"].height - @sprites["textbox"].height) + 32
    win = KifRandOptionWindow.new(@PokemonOptions, 0, @sprites["title"].height, width, height)
    win.viewport = @viewport
    win.visible = true
    return win
  end
end

class KifRandPageScene < PokemonOption_Scene
  include KifRandWindowMixin

  def initialize(title, desc, colors, builder)
    super()
    @kif_title = title
    @kif_desc = desc
    @kif_colors = colors
    @kif_builder = builder
  end

  def initUIElements
    super
    @sprites["title"].text = @kif_title
  end

  def getDefaultDescription
    return @kif_desc
  end

  def pbStartScene(inloadscreen = false)
    super
    if @kif_colors
      @sprites["option"].nameBaseColor = @kif_colors[0]
      @sprites["option"].nameShadowColor = @kif_colors[1]
    else
      @sprites["option"].nameBaseColor = MessageConfig::BLUE_TEXT_MAIN_COLOR
      @sprites["option"].nameShadowColor = MessageConfig::BLUE_TEXT_SHADOW_COLOR
    end
    @sprites["option"].refresh
  end

  def pbGetOptions(inloadscreen = false)
    return @kif_builder.call
  end

  def pbEndScene
    super
    KIF::Rand.sync_masters
  end
end

class RandomizerOptionsScene < PokemonOption_Scene
  include KifRandWindowMixin

  def initialize
    super
    $game_switches[SWITCH_RANDOMIZED_AT_LEAST_ONCE] = true
    KIF::Rand.seed
  end

  def initUIElements
    super
    @sprites["title"].text = _INTL("Randomizer")
  end

  def getDefaultDescription
    return _INTL("Same seed + same settings = the same game.")
  end

  def pbStartScene(inloadscreen = false)
    super
    @sprites["option"].nameBaseColor = MessageConfig::BLUE_TEXT_MAIN_COLOR
    @sprites["option"].nameShadowColor = MessageConfig::BLUE_TEXT_SHADOW_COLOR
    @sprites["option"].refresh
    @sprites["textbox"].text = getDefaultDescription
  end

  def kif_refresh
    @sprites["option"].refresh if @sprites && @sprites["option"]
  end

  def pbGetOptions(inloadscreen = false)
    r = KIF::Rand
    options = []
    options << r::DynButton.new(proc { _INTL("Seed: {1}", r.format_seed) },
                                proc { r.seed_menu; kif_refresh },
                                _INTL("Same seed + same settings = the same game."))
    options << ButtonOption.new(_INTL("Presets & sharing"), proc { r.page_presets; kif_refresh },
                                _INTL("Copy, paste, save or load settings."))
    options << EnumOption.new(_INTL("Spoiler log"), [_INTL("Off"), _INTL("On")],
                              proc { r.log_on? ? 1 : 0 },
                              proc { |v| r.data[:log] = (v == 1) },
                              [_INTL("No spoiler log is written."),
                               _INTL("Writes \"Randomizer Log - <seed>.txt\" in the Randomizer/Logs folder.")])
    options << ButtonOption.new(_INTL("View spoiler log"), proc { r.view_log },
                                _INTL("Shows everything that was randomized (asks first)."))
    [[:pokemon, _INTL("Pokémon"), _INTL("Wild encounters, starters, statics, gifts and trades.")],
     [:trainers, _INTL("Trainers"), _INTL("Trainer teams, class themes and team size.")],
     [:gyms, _INTL("Gyms"), _INTL("Gym trainers, leaders and gym types.")],
     [:items, _INTL("Items"), _INTL("Found, given and shop items, TMs.")],
     [:data, _INTL("Pokémon data"), _INTL("Types, moves, abilities and base stats.")],
     [:evolutions, _INTL("Evolutions"), _INTL("What each Pokémon evolves into.")],
     [:exclusions, _INTL("Exclusions"), _INTL("Pokémon, moves and abilities never picked.")]].each do |page, label, desc|
      options << r::DynButton.new(proc { "#{label} (#{r.page_state(page)})" },
                                  proc { r.send("page_#{page}"); kif_refresh }, desc)
    end
    unless $game_switches[SWITCH_DURING_INTRO]
      options << ButtonOption.new(_INTL("Randomize now"), proc {
        if pbConfirmMessage(_INTL("Randomize with seed {1}? Your current randomized Pokémon, trainers and items are replaced. Your party and boxes stay.", r.format_seed))
          r.randomize_now
          pbMessage(_INTL("Done!"))
        end
      }, _INTL("Applies these settings now."))
    end
    return options
  end

  def pbEndScene
    super
    KIF::Rand.sync_masters
    if $game_switches[SWITCH_DURING_INTRO]
      KIF::Rand.screen_closed!
      # The intro's events shuffle the Pokédex/trainers next; the Pokémon data
      # is made first so those shuffles see the new base stats
      if KIF::Rand.data_on?
        KIF::Rand.randomize_data
        KIF::Rand.write_log   # the intro shuffles rewrite it if they run
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Cody Settings button (randomized saves only)
#-------------------------------------------------------------------------------
class CodyOptionsScene < KifOptionsScene
  alias kif_rand_pbGetOptions pbGetOptions unless method_defined?(:kif_rand_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_rand_pbGetOptions(inloadscreen)
    if !inloadscreen && KIF::Rand.available?
      options << ButtonOption.new(_INTL("Randomizer"), proc {
        pbFadeOutIn {
          PokemonOptionScreen.new(RandomizerOptionsScene.new).pbStartScreen
        }
      }, _INTL("Seed, presets, spoiler log and every randomizer setting."))
    end
    return options
  end
end
