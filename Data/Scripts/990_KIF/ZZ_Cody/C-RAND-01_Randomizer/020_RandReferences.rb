#===============================================================================
# C-RAND-01 – PIF 6.9 parts of the randomizer (2026-11-02)
#   * References filter (Trainers page): trainer teams only use sprites from the
#     reference sets the player picks. PIF keeps it in switch 1187
#     (SWITCH_RANDOM_REFERENCE_SPRITES), the picked sets in
#     $PokemonSystem.selected_reference_sprite_categories and the sprite names in
#     one file shared by every save (Data/sprites/SELECTED_REFERENCES). PIF's
#     Kernel.pbShuffleTrainersCustom already turns the file into the list KIF's
#     shuffle gets, so this adds the setting, the picker button, and makes the
#     file follow the save's own sets. It needs Custom sprites only (as in PIF).
#     Off by default; not part of a settings code while Off.
#   * One progress bar: while a seeded shuffle runs, PIF's bar (ShuffleProgressBar)
#     is the seeded bar of 001_RandCore.rb instead of a second one.
#   * Trainer egg groups: PIF 6.9's trainer shuffle hands the "trainers are
#     random" switch to getNewSpecies as its egg group flag, so every trainer
#     Pokémon had to share an egg group with the old one. KIF passes the real
#     flag (switch 1148, off unless set).
#===============================================================================
module KIF
  module Rand
    # Added last, so older settings codes still line up (not in DATA_KEYS: the switch is the value)
    REFERENCE_SETTINGS = [[:ref_filter, :enum, 2]]
    REFERENCE_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_SETTINGS.any? { |s| s[0] == st[0] } }
    LABELS[:ref_filter] = ["References filter", ["Off", "On"]]

    INCLUDE_NON_REFERENCE = "Include non-reference"   # PIF's picker entry

    # The reference sets this save picked, or nil (never picked = all sets)
    def self.ref_categories
      ps = $PokemonSystem
      c = ps.respond_to?(:selected_reference_sprite_categories) ? ps.selected_reference_sprite_categories : nil
      return (c.is_a?(Array) && !c.empty?) ? c : nil
    end

    # Plain, order-free form for the settings draft
    def self.ref_signature
      c = ref_categories
      return c ? c.map(&:to_s).sort : nil
    end

    def self.ref_signature=(list)
      ps = $PokemonSystem
      return unless ps.respond_to?(:selected_reference_sprite_categories=)
      ps.selected_reference_sprite_categories = list.is_a?(Array) ? list.dup : nil
      @ref_written = nil
    end

    def self.ref_label
      c = ref_categories
      return c ? _INTL("{1} chosen", c.length) : _INTL("all")
    end

    # PIF reads the sprites from one file for every save; this save's own sets
    # are written to it before they are used (once per change)
    def self.sync_references
      return false unless sw(SWITCH_RANDOM_REFERENCE_SPRITES)
      sig = ref_signature
      return true if @ref_written == [sig]
      map = map_sprites_by_reference
      keys = sig || map.keys
      map[INCLUDE_NON_REFERENCE] = getNonReferenceSprites(nil, map) if keys.include?(INCLUDE_NON_REFERENCE)
      keys = keys.select { |k| map.key?(k) }
      write_selected_references_to_file(keys, map)
      @ref_written = [sig]
      return true
    rescue => e
      KIF.log("Randomizer: the reference list couldn't be written (#{e.class}: #{e.message})")
      return false
    end

    # PIF's picker (full screen); it saves the choice and writes the file itself
    def self.pick_references
      pbFadeOutIn { select_randomizer_references(200) }
      @ref_written = nil
    rescue => e
      KIF.log("Randomizer: the reference picker failed (#{e.class}: #{e.message})")
      pbMessage(_INTL("The reference list couldn't be opened."))
    end

    #---------------------------------------------------------------------------
    # One progress bar
    #---------------------------------------------------------------------------
    # Stands in for PIF's ShuffleProgressBar during a seeded shuffle: the same
    # calls, drawn by the seeded bar (which doesn't update the map)
    class SeededBar
      def initialize(text = "")
        @text = text
        @done = false
      end

      def progress=(frac)
        KIF::Rand.progress(@text, frac) unless @done
      end

      def update; end

      def dispose
        @done = true
      end

      def disposed?
        return @done
      end
    end

    #---------------------------------------------------------------------------
    # Trainer egg groups (see the top)
    #---------------------------------------------------------------------------
    @trainer_pass = false

    def self.trainer_egg_group?
      return sw(SWITCH_RANDOM_TRAINER_EGG_GROUP)
    end

    # PIF's trainer shuffle runs in the block
    def self.in_pif_trainer_shuffle
      was = @trainer_pass
      @trainer_pass = true
      begin
        return yield
      ensure
        @trainer_pass = was
      end
    end

    # getNewSpecies / getNewCustomSpecies arguments with the real egg group flag (the 6th)
    def self.egg_args(args)
      return args unless @trainer_pass && args.length >= 6
      a = args.dup
      a[5] = trainer_egg_group?
      return a
    end

    # One set of lookup tables for a whole trainer shuffle (PIF 6.9's
    # getNewCustomSpecies fills and reuses them; the picks are the same without)
    def self.pick_caches
      @pick_caches ||= [new_bst_cache, new_egg_group_cache, new_legendary_cache, {}]
      return @pick_caches
    end

    def self.reset_pick_caches
      @pick_caches = nil
    end
  end
end

class << ShuffleProgressBar
  alias kif_rand_new new unless method_defined?(:kif_rand_new)

  def new(*args, &blk)
    return KIF::Rand::SeededBar.new(*args) if KIF::Rand.seeded > 0
    return kif_rand_new(*args, &blk)
  end
end

# The sprite loader and the shuffle both read the file: it holds this save's sets first
class Object
  alias kif_rand_getSelectedReferenceSprites getSelectedReferenceSprites unless method_defined?(:kif_rand_getSelectedReferenceSprites) || private_method_defined?(:kif_rand_getSelectedReferenceSprites)

  def getSelectedReferenceSprites(*args)
    KIF::Rand.sync_references
    return kif_rand_getSelectedReferenceSprites(*args)
  end
end
