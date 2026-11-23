#===============================================================================
# SCOPE-02 – PIF fix: the battle sprite loader with no sprite
# load_pif_sprite_directly(nil) read nil.type and raised NoMethodError, though
# its callers check for a nil result (an unset pif_sprite); it now returns nil.
# preload is PIF's own, without the console line it printed on every call.
#===============================================================================
module KIF
  module SpriteLoaderGuard
    def load_pif_sprite_directly(pif_sprite)
      return nil if pif_sprite.nil?
      super
    end

    def preload(pif_sprite)
      previous_download_allowed = @download_allowed
      @download_allowed = false
      load_random_alt_for_pif_sprite(pif_sprite)
      @download_allowed = previous_download_allowed
    end
  end
end

BattleSpriteLoader.prepend(KIF::SpriteLoaderGuard) unless BattleSpriteLoader.ancestors.include?(KIF::SpriteLoaderGuard)
