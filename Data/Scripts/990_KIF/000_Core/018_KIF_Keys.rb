#===============================================================================
# Key names for KIF's screens: which keyboard key the player has bound to a
# game button, read from mkxp-z's keybindings file (the player's copy in the
# save folder, else the game's Data/keybindings.mkxp1). So a screen can say
# "D" for Input::SPECIAL instead of guessing.
# File: three Int32 (version, ?, count), then count entries of four Int32:
# source type (1 key, 2 controller button, 3 axis), code (SDL scancode /
# button / axis), extra, target button (Input::C, Input::L...).
# While a controller is what the player pressed last (C-SYS-08 watches),
# the controller button bound to it is named instead ("B", not "Esc": a
# controller player was told "Esc" in the 26 Oct test).
#===============================================================================
module KIF
  module Keys
    FILE = "keybindings.mkxp1"

    # SDL scancode => [label shown, mkxp-z key symbol]
    NAMES = {}
    ("A".."Z").each_with_index { |c, i| NAMES[4 + i] = [c, c.to_sym] }
    (1..9).each { |n| NAMES[29 + n] = [n.to_s, :"N#{n}"] }
    NAMES[39] = ["0", :N0]
    {
      40 => ["Enter", :RETURN], 41 => ["Esc", :ESCAPE], 42 => ["Bksp", :BACKSPACE],
      43 => ["Tab", :TAB], 44 => ["Space", :SPACE], 73 => ["Ins", :INSERT],
      74 => ["Home", :HOME], 75 => ["PgUp", :PAGEUP], 76 => ["Del", :DELETE],
      77 => ["End", :END], 78 => ["PgDn", :PAGEDOWN], 79 => ["Right", :RIGHT],
      80 => ["Left", :LEFT], 81 => ["Down", :DOWN], 82 => ["Up", :UP],
      88 => ["Enter", :KP_ENTER], 98 => ["Num0", :KP_0],
      224 => ["Ctrl", :LCTRL], 225 => ["Shift", :LSHIFT], 226 => ["Alt", :LALT],
      228 => ["Ctrl", :RCTRL], 229 => ["Shift", :RSHIFT], 230 => ["Alt", :RALT]
    }.each { |k, v| NAMES[k] = v }
    (1..12).each { |n| NAMES[57 + n] = ["F#{n}", :"F#{n}"] }
    (1..9).each { |n| NAMES[88 + n] = ["Num#{n}", :"KP_#{n}"] }

    # SDL's controller buttons (in its order) and triggers, by their Xbox names as SDL gives them
    PAD_BUTTONS = %w[A B X Y Back Guide Start L3 R3 LB RB Up Down Left Right]
    PAD_AXES = { 4 => "LT", 5 => "RT" }

    module_function

    def paths
      list = []
      dir = (System.data_directory rescue nil).to_s
      list << dir + FILE unless dir.empty?
      list << File.join("Data", FILE)
      return list
    end

    # button => [scancode, ...] (keyboard only), re-read when the file changes
    def bindings
      return read_file[0]
    end

    # button => [controller button name, ...]
    def pad_bindings
      return read_file[1]
    end

    def read_file
      path = paths.find { |p| File.file?(p) }
      return [{}, {}] unless path
      stamp = [path, File.mtime(path).to_f, File.size(path)]
      return @read if @read && @stamp == stamp
      @stamp = stamp
      keys = {}
      pads = {}
      data = File.binread(path)
      n = data[8, 4].to_s.unpack1("l<").to_i
      n.times do |i|
        t, code, _extra, target = data[12 + i * 16, 16].to_s.unpack("l<4")
        break if target.nil?
        (keys[target] ||= []) << code if t == 1
        nm = (t == 2 && code >= 0) ? PAD_BUTTONS[code] : (t == 3 ? PAD_AXES[code] : nil)
        (pads[target] ||= []) << nm if nm
      end
      return @read = [keys, pads]
    rescue StandardError
      return @read = [{}, {}]
    end

    # mkxp-z's own controller layout (the game's Data/keybindings.mkxp1)
    def pad_defaults
      return @pad_defaults ||= {
        Input::USE => "A", Input::BACK => "B", Input::ACTION => "X", Input::X => "Y",
        Input::Y => "L3", Input::SPECIAL => "R3", Input::JUMPUP => "LB", Input::JUMPDOWN => "RB"
      }
    end

    # a controller button was pressed more recently than a key
    def pad?
      return defined?(KIF::ControllerLog) && KIF::ControllerLog.respond_to?(:pad?) && KIF::ControllerLog.pad? ? true : false
    end

    def pad_label(button)
      return (pad_bindings[button] || []).first || pad_defaults[button]
    end

    # what to print for a button ("D"); default when nothing is bound
    def label(button, default = nil)
      return pad_label(button) || default if pad?
      (bindings[button] || []).each do |code|
        return NAMES[code][0] if NAMES[code]
      end
      return default
    end

    # What a screen prints for a button: the player's key, else the game's
    # default one. short: the shortest bound key ("Z" rather than "Shift"),
    # for tight spots.
    def defaults
      return @defaults ||= {
        Input::USE => "C", Input::BACK => "X", Input::ACTION => "Z",
        Input::SPECIAL => "D", Input::JUMPUP => "Q", Input::JUMPDOWN => "W",
        Input::Y => "S"
      }
    end

    # Phones: the on-screen pad's button letters (no keyboard to name)
    def pad
      return @pad ||= %w[A B C X Y Z L R].each_with_object({}) do |c, h|
        h[Input.const_get(c)] ||= c if Input.const_defined?(c)
      end
    end

    def name(button)
      return pad[button] || "?" if KIF.mobile?
      return label(button, defaults[button] || "?")
    end

    def short(button)
      return pad[button] || "?" if KIF.mobile?
      return pad_label(button) || defaults[button] || "?" if pad?
      names = (bindings[button] || []).map { |c| NAMES[c] && NAMES[c][0] }.compact
      return names.min_by(&:length) || defaults[button] || "?"
    end

    # "{USE}", "{ACTION}"... in a text -> the keys (for descriptions written
    # once)
    def fill(text)
      return text.to_s.gsub(/\{(USE|BACK|ACTION|SPECIAL|JUMPUP|JUMPDOWN|X|Y)\}/) { name(Input.const_get($1)) }
    end

    # the mkxp-z symbols (for Input.triggerex?) of the keys bound to button
    def symbols(button)
      return (bindings[button] || []).map { |c| NAMES[c] && NAMES[c][1] }.compact
    end
  end
end
