class SpritesBitmapCache
  @@cache = {} # Cache storage for individual sprites
  @@usage_order = [] # Tracks usage order for LRU eviction

  def getCache()
    return @@cache
  end

  def get_bitmap(pif_sprite)
    sprite_key = get_cache_key(pif_sprite)
    if @@cache.key?(sprite_key)
      mark_key_as_recently_used(sprite_key)
      return @@cache[sprite_key].clone
    end
    return nil
  end

  def mark_key_as_recently_used(sprite_key)
    @@usage_order.delete(sprite_key)
    @@usage_order << sprite_key
  end

  #Keys format: [type]_B[body]H[head]_letter
  # ex:
  # AUTOGEN_B12H12_
  # CUSTOM_B12H12_a
  # BASE_BH12_a
  # etc.
  def get_cache_key(pif_sprite)
    return "#{pif_sprite.type.to_s}_B#{pif_sprite.body_id}H#{pif_sprite.head_id}_#{pif_sprite.alt_letter}".to_sym
  end

  #Keys format: AUTOGEN_B12H12_a
  def add(pif_sprite,bitmap)
    sprite_key = get_cache_key(pif_sprite)
    echoln "adding key #{sprite_key} to cache"
    @@cache[sprite_key] = bitmap.clone

    if @@cache.size >= Settings::SPRITE_CACHE_MAX_NB
      # Evict least recently used (first in order)
      oldest_key = @@usage_order.shift
      @@cache.delete(oldest_key)
      echoln "Evicted: #{oldest_key} from sprite cache"
    end
    @@usage_order << sprite_key
  end

  def clear
    @@cache = {}
    @@usage_order = []
  end
end
