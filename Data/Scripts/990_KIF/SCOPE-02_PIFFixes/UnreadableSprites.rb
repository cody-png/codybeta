#===============================================================================
# SCOPE-02 – a custom sprite file the engine can't read (2026-10-24)
#   A file in Graphics/CustomBattlers/local_sprites that isn't a real PNG (a
#   broken download, a renamed WebP/JPG from a sprite pack) crashed the game
#   with "Error loading image '...': Unsupported image format" wherever that
#   Pokémon was drawn (bug report: fusing two Nidorans, 32.29.png). PIF falls
#   back to the sprite sheet / autogen only when the file is missing; now an
#   unreadable file is treated the same: noted once in the log (so the player
#   can delete or replace it) and skipped for the rest of the session.
#===============================================================================
module KIF
  module UnreadableSprites
    LOCAL = "local_sprites/"
    # mkxp-z's SDLError isn't a StandardError: PIF's own plain `rescue` lets it through
    ERRORS = [StandardError, (Object.const_get(:SDLError) rescue nil)].compact
    @bad = {}

    module_function

    def bad?(path); !path.nil? && @bad[path.to_s.downcase] == true; end

    # the file named in the engine's message, if it is a player's local sprite
    def path_in(e)
      p = e.message.to_s[/loading image '([^']+)'/, 1]
      return p && p.include?(LOCAL) ? p : nil
    end

    def mark(path, e)
      return if bad?(path)
      @bad[path.to_s.downcase] = true
      KIF.log("Picture file can't be read, skipped (delete or replace it): #{path} (#{e.message.to_s[0, 160]})")
    end

    # Bitmap.new(path), or nil (noted once) when the file isn't a picture
    def read(path)
      return nil if path.nil? || bad?(path)
      return Bitmap.new(path)
    rescue *ERRORS => e
      mark(path, e)
      return nil
    end

    # the sprite in hand and the saved sprite choices stop pointing at it
    def forget(sprite)
      list = [sprite]
      list.concat($PokemonSystem.alt_sprite_substitutions.values) if $PokemonSystem && $PokemonSystem.alt_sprite_substitutions.is_a?(Hash)
      list.each { |s| s.local_path = nil if s.respond_to?(:local_path=) && bad?(s.local_path) }
    end

    module Loader
      def check_for_local_sprite(pif_sprite)
        path = super
        return KIF::UnreadableSprites.bad?(path) ? nil : path
      end

      def load_pif_sprite_directly(pif_sprite)
        return kif_skip_unreadable(pif_sprite) { super }
      end

      def load_fusion_sprite(head_id, body_id)
        return kif_skip_unreadable(nil) { super }
      end

      def load_base_sprite(dex_number)
        return kif_skip_unreadable(nil) { super }
      end

      # Once more without the file (the second try's errors are PIF's own)
      def kif_skip_unreadable(pif_sprite)
        return yield
      rescue *KIF::UnreadableSprites::ERRORS => e
        path = KIF::UnreadableSprites.path_in(e)
        raise unless path
        KIF::UnreadableSprites.mark(path, e)
        KIF::UnreadableSprites.forget(pif_sprite)
        return yield
      end
    end
  end
end

BattleSpriteLoader.prepend(KIF::UnreadableSprites::Loader) if defined?(BattleSpriteLoader)
