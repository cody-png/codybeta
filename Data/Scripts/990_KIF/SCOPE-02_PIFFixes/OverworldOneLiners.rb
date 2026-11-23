# A footprint that goes away removes itself from the sprite list; before, the loop skipped entries as it deleted.
class Footsprite
  def dispose
    return if @disposed
    @disposed = true
    @event.erase
    @chardata.delete(@rsprite)
    @rsprite.dispose
    @sprite.dispose
    @sprite = nil
  end
end

# The lightning overlay sprite was never disposed with the weather (dispose looked for @lightning_sprite).
class RPG::Weather
  alias kif_orig_dispose dispose unless method_defined?(:kif_orig_dispose)

  def dispose
    @lightning_overlay.dispose if @lightning_overlay && !@lightning_overlay.disposed?
    kif_orig_dispose
  end
end

# A Pokemon with no level printed an empty one; it reads ??? now.
class Pokemon
  def inspect
    str = super.chop
    str << format(' %s Lv.%s>', @species, @level || '???')
    return str
  end
end

# notice_icon.png does not ship, and a wild Pokemon noticing the player crashed on the missing bitmap; an empty icon stands in.
class OverworldNoticeIcon
  alias kif_orig_load_icon_bitmap load_icon_bitmap unless method_defined?(:kif_orig_load_icon_bitmap)

  def load_icon_bitmap(behavior)
    return kif_orig_load_icon_bitmap(behavior) || Bitmap.new(1, 1)
  end
end

# An outfit entry with no id is skipped, so it cannot be counted as an outfit.
alias kif_orig_update_global_hats_list update_global_hats_list unless defined?(kif_orig_update_global_hats_list)
alias kif_orig_update_global_hairstyles_list update_global_hairstyles_list unless defined?(kif_orig_update_global_hairstyles_list)
alias kif_orig_update_global_clothes_list update_global_clothes_list unless defined?(kif_orig_update_global_clothes_list)

def update_global_hats_list()
  kif_orig_update_global_hats_list
  $PokemonGlobal.hats_data.delete(nil)
end

def update_global_hairstyles_list()
  kif_orig_update_global_hairstyles_list
  $PokemonGlobal.hairstyles_data.delete(nil)
end

def update_global_clothes_list()
  kif_orig_update_global_clothes_list
  $PokemonGlobal.clothes_data.delete(nil)
end
