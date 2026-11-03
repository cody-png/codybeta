#===============================================================================
# F-BATTLE-12 - EBDX battler shadows sit under the feet (Bishsume, v1.2.13:
# "pokemon sprites are uniformly and consistently hovering above their shadows")
# 660/010 puts the round shadow at the bottom of the sprite's bitmap. PIF's
# battle sprites keep 15-45 source px (x2 on screen) of empty canvas under the
# feet, and PIF's classic scene makes up for it with each species' battler
# metrics, which EBDX's own positioning never applies. So the shadow lay 30-90
# px below the feet. The gap is measured from the bitmap itself, so every
# sprite is covered (fused, triple fused, custom, imported, shiny, back).
# A hovering foe (BattlerAltitude) keeps its gap as PIF's scene does (it raises
# the sprite by altitude * 2; foes only), up to the old spot at the canvas bottom.
# The shadow also ignores the idle bob (SCOPE-02_PIFFixes/BattleBob.rb): it stays on the ground.
# Nothing here runs when EBDX isn't installed.
#===============================================================================
module KIF
  module EBDX
    FEET_ALPHA = 80   # a pixel at least this opaque (0-255) is part of the sprite

    # transparent rows under the sprite's lowest opaque pixel (0: it touches the bottom)
    def self.feet_gap(bmp)
      return 0 if bmp.nil? || bmp.disposed?
      h = bmp.height
      seen = bmp.instance_variable_get(:@kif_feet_gap)
      return seen[1] if seen && seen[0] == h
      gap = begin
        scan_feet_gap(bmp)
      rescue StandardError
        0   # remembered too, so a bitmap that can't be read isn't scanned again every frame
      end
      bmp.instance_variable_set(:@kif_feet_gap, [h, gap])
      return gap
    rescue StandardError
      return 0
    end

    # shortcut: without Bitmap#raw_data every 2nd column is read, so a 1 px wide foot can be missed
    def self.scan_feet_gap(bmp)
      w = bmp.width
      h = bmp.height
      if bmp.respond_to?(:raw_data)
        raw = bmp.raw_data   # 0xRRGGBBAA per pixel, top row first, as in F-SHINY-01
        stride = w * 4
        trusted = true
        (h - 1).downto(0) do |y|
          x = raw.byteslice(y * stride, stride).unpack("N*").index { |px| (px & 0xFF) >= FEET_ALPHA }
          next unless x
          return h - 1 - y if bmp.get_pixel(x, y).alpha >= FEET_ALPHA
          trusted = false   # raw_data is not laid out as assumed: read the pixels instead
          break
        end
        return 0 if trusted
      end
      (h - 1).downto(0) do |y|
        (0...w).step(2) { |x| return h - 1 - y if bmp.get_pixel(x, y).alpha >= FEET_ALPHA }
      end
      return 0
    end

    # Screen y of the ground under a sprite drawn at y with origin oy and
    # vertical zoom: its feet, plus a hovering foe's altitude (PIF: altitude * 2),
    # never below the bitmap's bottom edge.
    def self.ground_y(y, oy, zoom_y, height, gap, altitude = 0)
      feet = y - (oy - (height - gap)) * zoom_y
      bottom = y + (height - oy) * zoom_y
      return [feet + altitude * 2 * zoom_y, bottom].min
    end

    # the sprite hash keys, made once (this runs for every battler every frame)
    RSHADOW_KEYS = Array.new(6) { |i| "rshadow_#{i}".freeze }.freeze
    POKEMON_KEYS = Array.new(6) { |i| "pokemon_#{i}".freeze }.freeze

    module BattlerShadow
      def ebdxUpdateRoundShadow(i)
        super
        rs = @sprites[RSHADOW_KEYS[i] || "rshadow_#{i}"]
        pk = @sprites[POKEMON_KEYS[i] || "pokemon_#{i}"]
        return if !rs || rs.disposed? || !rs.visible || !pk
        bmp = pk.bitmap
        return if !bmp || bmp.disposed?
        # an animated strip (C-BATTLE-04) stands on its first frame's feet
        frames = pk.instance_variable_get(:@kif_frames)
        gap = KIF::EBDX.feet_gap(frames ? frames[0] : bmp)
        altitude = (i % 2 == 1) ? ((pk.pkmn.species_data.front_sprite_altitude rescue 0) || 0) : 0
        # pk.y is the sprite's place without the bob; the ellipse is centred on the feet line
        rs.y = KIF::EBDX.ground_y(pk.y, pk.oy, pk.zoom_y, bmp.height, gap, altitude) + rs.bitmap.height * rs.zoom_y / 2
      end
    end
  end
end

if KIF::EBDX.installed? && defined?(::PokeBattle_SceneEBDX)
  ::PokeBattle_SceneEBDX.prepend(KIF::EBDX::BattlerShadow)
end
