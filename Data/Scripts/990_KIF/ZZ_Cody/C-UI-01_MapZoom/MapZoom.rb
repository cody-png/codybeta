#===============================================================================
# C-UI-01 – Map Zoom (2026-10-27)
#   Options > Graphics > Overworld > "Map Zoom": Normal (PIF's 2x pixels),
#   Far (1x: 16 px tiles). Global setting. (A 1.5x level was tried and
#   dropped 2026-10-27: 2x2 art pixels can't land evenly on 1.5x.)
#   New in KIF (0.20.7 never had it); Normal is the default, so Classic KIF
#   stays as PIF draws it.
#   How: every map tile sprite is drawn smaller and the tile grid is made
#   larger to fill the screen; characters, shadows, reflections, surf bases,
#   grass rustles, emotes, fog and the cave darkness circle are scaled the
#   same way and the camera centres on a larger view. Windows, menus, the map
#   name sign, weather and screen tone are on other viewports and stay as
#   they are.
#   Camera at Far: it stops at a map edge with no connected map on
#   that side; a map smaller than the view (on an axis with no connections)
#   is centred. Dark maps keep the camera on the player (the light circle is
#   drawn round the screen centre), their edges are black anyway.
#   A mod with its own map zoom switched on takes over: this setting then
#   works as Normal until the mod's zoom is Off.
#   6.8.2 bases: 006_Map renderer/001_TilemapRenderer.rb, 004_Game classes/
#   007_Game_Character.rb (screen_x/y/z), 009_Game_Player.rb (center),
#   006_Game_MapFactory.rb (mapInRange?), 005_Sprites/*.
#===============================================================================
KIF::Options.define(:kif_mapzoom, 0, :global)   # index into KIF::MapZoom::LEVELS

module KIF
  module MapZoom
    LEVELS = [1.0, 0.5]
    FOLDER = "C-UI-01_MapZoom"

    @scale = nil      # the zoom in use (1.0 = Normal)
    @sides = {}
    @warned = false

    # The zoom the setting asks for, 1.0 when the feature is off or a mod zooms
    def self.wanted
      return 1.0 unless $PokemonSystem
      return 1.0 if defined?(KIF::Modules) && !KIF::Modules.active?(FOLDER)
      s = LEVELS[level] || 1.0
      return 1.0 if s != 1.0 && mod_zoom?
      return s
    end

    # The chosen level. Saves from before 1.5x was dropped had 1 = 1.5x and
    # 2 = 1x: both are the new Far (1)
    def self.level
      i = $PokemonSystem.kif_mapzoom.to_i
      return i <= 1 ? [i, 0].max : 1
    end

    # A mod's own zoom (e.g. a camera mod) is on: KIF's zoom waits, so the map
    # is never zoomed twice
    def self.mod_zoom?
      return false unless defined?(::OverworldZoom)
      on = (::OverworldZoom.desired_scale < 1.0 || ::OverworldZoom.tilt_enabled?) rescue false
      if on && !@warned
        @warned = true
        KIF.log("Map Zoom: a mod's own map zoom is on; KIF's Map Zoom stays at Normal until it is Off")
      end
      return on
    end

    def self.scale
      return @scale ||= wanted
    end

    def self.zoomed?
      return scale != 1.0
    end

    # Called every map frame and when the setting/module changes
    def self.sync
      w = wanted
      return if w == @scale
      @scale = w
      apply!
    end

    # Bring what's on screen to the current zoom (no scene rebuild needed)
    def self.apply!
      s = scale
      KIF.log("Map Zoom: #{s == 1.0 ? 'Normal' : "#{(s * 2).round(2)}x"}") rescue nil
      return unless defined?(Scene_Map) && $scene.is_a?(Scene_Map)
      sets = ($scene.spritesets || {}).values.compact rescue []
      sets.each do |ss|
        (ss.instance_variable_get(:@character_sprites) || []).each { |sp| zoom_sprite(sp, s) }
      end
      g = $scene.spritesetGlobal rescue nil
      ps = g && g.playersprite
      if ps && !ps.disposed?
        zoom_sprite(ps, s)
        ps.mz_wearables.each { |w| w.zoom_x = s; w.zoom_y = s } if ps.respond_to?(:mz_wearables)
      end
      d = $PokemonTemp && $PokemonTemp.darknessSprite
      d.refresh if d && !d.disposed?
      $game_player.center($game_player.x, $game_player.y) if $game_player && $game_map
      r = $scene.map_renderer rescue nil
      r.refresh if r && !r.disposed?
    end

    def self.zoom_sprite(sp, s)
      return if !sp || sp.disposed?
      sp.zoom_x = s
      sp.zoom_y = s
    end

    #---------------------------------------------------------------------------
    # Camera
    #---------------------------------------------------------------------------
    # The view in map pixels * subpixels
    def self.view_w; return Graphics.width / scale * Game_Map::X_SUBPIXELS; end
    def self.view_h; return Graphics.height / scale * Game_Map::Y_SUBPIXELS; end

    # display_x/y that put map tile (x, y) at the centre of the zoomed view
    def self.center_x; return ((Graphics.width / scale / 2.0) - Game_Map::TILE_WIDTH / 2) * Game_Map::X_SUBPIXELS; end
    def self.center_y; return ((Graphics.height / scale / 2.0) - Game_Map::TILE_HEIGHT / 2) * Game_Map::Y_SUBPIXELS; end

    # Which edges of a map have a connected map beyond them
    def self.sides(map_id)
      return @sides[map_id] ||= begin
        ret = {}
        w, h = MapFactoryHelper.getMapDims(map_id)
        (MapFactoryHelper.getMapConnections[map_id] || []).each do |c|
          if c[0] == map_id
            other = c[3]; ox = c[1] - c[4]; oy = c[2] - c[5]
          else
            other = c[0]; ox = c[4] - c[1]; oy = c[5] - c[2]
          end
          ow, oh = MapFactoryHelper.getMapDims(other)
          across = ox < w && ox + ow > 0     # beside the map, not off a corner
          down   = oy < h && oy + oh > 0
          ret[:n] = true if across && oy + oh <= 0
          ret[:s] = true if across && oy >= h
          ret[:w] = true if down && ox + ow <= 0
          ret[:e] = true if down && ox >= w
        end
        ret
      end
    end

    def self.dark?(map)
      md = GameData::MapMetadata.try_get(map.map_id)
      return true if md && md.dark_map
      return (darknessEffectOnMap(map.map_id) ? true : false) rescue false
    end

    # One axis: a small unconnected map is centred, otherwise the camera
    # stops at an edge with nothing beyond it
    def self.clamp_axis(v, size, view, lo_open, hi_open)
      return ((size - view) / 2.0).round if size <= view && !lo_open && !hi_open
      v = [v, 0].max unless lo_open
      v = [v, size - view].min unless hi_open
      return v
    end

    def self.clamp(map, dx, dy)
      return [dx, dy] if dark?(map)
      sd = sides(map.map_id)
      x = clamp_axis(dx, map.width * Game_Map::REAL_RES_X, view_w, sd[:w], sd[:e])
      y = clamp_axis(dy, map.height * Game_Map::REAL_RES_Y, view_h, sd[:n], sd[:s])
      return [x.round, y.round]
    end

    # Point a scaled offset back at its anchor: anchor + (v - anchor) * scale
    def self.toward(anchor, v, s = scale)
      return anchor + ((v - anchor) * s).round
    end
  end
end

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Map Zoom"), [_INTL("Normal"), _INTL("Far"), _INTL("Farthest")],
                 proc { $PokemonSystem.kif_mapzoom },
                 proc { |value| $PokemonSystem.kif_mapzoom = value; KIF::MapZoom.sync },
                 [_INTL("The overworld at its normal size."),
                  _INTL("Zooms the overworld out: map pixels are drawn at 1.5x, so you see more of the map."),
                  _INTL("Zooms the overworld out to 1x pixels: you see about four times as much of the map.")])
}
KIF::Modules.watch(:graphics) { |_on| KIF::MapZoom.sync } if defined?(KIF::Modules)

#-------------------------------------------------------------------------------
# Map tiles: smaller tiles, a larger grid
#-------------------------------------------------------------------------------
class TilemapRenderer
  alias mz_orig_update update unless method_defined?(:mz_orig_update) || private_method_defined?(:mz_orig_update)
  alias mz_orig_tile_coordinates refresh_tile_coordinates unless method_defined?(:mz_orig_tile_coordinates) || private_method_defined?(:mz_orig_tile_coordinates)
  alias mz_orig_tile_z refresh_tile_z unless method_defined?(:mz_orig_tile_z) || private_method_defined?(:mz_orig_tile_z)

  def update
    mz_fit_grid
    mz_orig_update
  end

  # Tiles enough to fill the screen at the current zoom (KIF's frame rate keeps
  # a spare ring of tiles while drawing in between: +3 instead of +1)
  def mz_fit_grid
    s = KIF::MapZoom.scale
    return if s == 1.0 && !@mz_grid
    extra = @kif_ring ? 3 : 1
    cols = (Graphics.width.to_f / (DISPLAY_TILE_WIDTH * s)).ceil + extra
    rows = (Graphics.height.to_f / (DISPLAY_TILE_HEIGHT * s)).ceil + extra
    return if @tiles.length == cols && @tiles_horizontal_count == cols && @tiles_vertical_count == rows
    @tiles.each { |col| col.each { |coord| coord.each { |tile| tile.dispose } } }
    @tiles_horizontal_count = cols
    @tiles_vertical_count = rows
    @tiles = Array.new(cols) { Array.new(rows) { Array.new(3) { TileSprite.new(@viewport) } } }
    @mz_grid = (s != 1.0)
    @old_tone = nil     # new tiles take the current tone/colour on this update
    @old_color = nil
    @need_refresh = true
  end

  # Zoomed: placed straight from the grid (one x/y set per tile, floor so every
  # column/row is exactly one zoomed tile from the next: rounding .5 away from
  # zero left a 1 px gap where the positions cross 0). Empty layers (no
  # bitmap, most of layers 2 and 3) are skipped: refresh_tile places a tile
  # when it gets a bitmap. KIF's frame-rate ring draws the grid one tile on.
  def refresh_tile_coordinates(tile, x, y)
    s = KIF::MapZoom.scale
    return mz_orig_tile_coordinates(tile, x, y) if s == 1.0
    return unless tile.visible
    if @kif_ring
      x -= 1
      y -= 1
    end
    tile.x = ((x * DISPLAY_TILE_WIDTH - @pixel_offset_x) * s).floor
    tile.y = ((y * DISPLAY_TILE_HEIGHT - @pixel_offset_y) * s).floor
  end

  # 6.8.2's rule (TilemapRenderer#refresh_tile_z), in the zoomed space of screen_z
  def refresh_tile_z(tile, map, y, layer, tile_id)
    s = KIF::MapZoom.scale
    return mz_orig_tile_z(tile, map, y, layer, tile_id) if s == 1.0
    return unless tile.visible
    y -= 1 if @kif_ring
    if tile.underwater_tile
      tile.z = -5
    elsif tile.bridge && $PokemonGlobal.bridge > 0
      tile.z = 0
    else
      priority = tile.priority
      tile.z = (priority == 0) ? 0 : ((y * DISPLAY_TILE_HEIGHT + priority * 32 + 32) * s).round
    end
  end

  # tiles get their size once, when their picture is set
  class TileSprite
    alias mz_orig_set_bitmap set_bitmap unless method_defined?(:mz_orig_set_bitmap) || private_method_defined?(:mz_orig_set_bitmap)

    def set_bitmap(filename, tile_id, autotile, animated, priority, bitmap)
      mz_orig_set_bitmap(filename, tile_id, autotile, animated, priority, bitmap)
      s = KIF::MapZoom.scale
      return if s == 1.0
      self.zoom_x = s
      self.zoom_y = s
    end
  end

  if method_defined?(:kif_fps_ring)
    alias mz_orig_fps_ring kif_fps_ring unless method_defined?(:mz_orig_fps_ring) || private_method_defined?(:mz_orig_fps_ring)

    # the frame rate's own rebuild is the normal size: fit it to the zoom again
    def kif_fps_ring(on)
      mz_orig_fps_ring(on)
      @mz_grid = true if KIF::MapZoom.scale != 1.0
      mz_fit_grid
    end
  end

  # Zoomed, the grid is about 3x PIF's (2835 tile sprites at 1x with the
  # frame-rate ring), so 6.8.2's TilemapRenderer#update (copied below, same
  # steps) runs its tile loop with less work per tile: no per-frame visited
  # table, coordinates and z set inline, and empty layers skipped.
  if method_defined?(:kif_fps_update)
    alias mz_orig_base_update kif_fps_update unless method_defined?(:mz_orig_base_update) || private_method_defined?(:mz_orig_base_update)

    def kif_fps_update
      return mz_orig_base_update if KIF::MapZoom.scale == 1.0
      mz_zoomed_update
    end
  end

  def mz_zoomed_update
    # Update tone / colour
    if @old_tone != @tone
      @tiles.each { |col| col.each { |coord| coord.each { |tile| tile.tone = @tone } } }
      @old_tone = @tone.clone
    end
    if @old_color != @color
      @tiles.each { |col| col.each { |coord| coord.each { |tile| tile.color = @color } } }
      @old_color = @color.clone
    end
    # Check for updated weather
    current_weather = $game_weather&.map_current_weather_type($game_map.map_id)
    if current_weather != @last_weather_type
      tileset_id = $game_map.tileset_id
      add_extra_autotiles(tileset_id, $game_map.map_id)
      refresh
      @last_weather_type = current_weather
    end
    # Recalculate autotile frames
    @tilesets.update
    @autotiles.update
    do_full_refresh = @need_refresh
    if @viewport.ox != @old_viewport_ox || @viewport.oy != @old_viewport_oy
      @old_viewport_ox = @viewport.ox
      @old_viewport_oy = @viewport.oy
      do_full_refresh = true
    end
    @screen_moved = false
    @screen_moved_vertically = false
    if $PokemonGlobal.bridge != @bridge
      @bridge = $PokemonGlobal.bridge
      @screen_moved_vertically = true
    end
    do_full_refresh = true if check_if_screen_moved
    cols = @tiles_horizontal_count
    rows = @tiles_vertical_count
    visited = (@mz_visited ||= [])
    visited.fill(false, 0, cols * rows)
    s = KIF::MapZoom.scale
    ring = @kif_ring ? 1 : 0
    moved = @screen_moved
    moved_v = @screen_moved_vertically
    frames = @autotiles.changed
    tw = DISPLAY_TILE_WIDTH
    th = DISPLAY_TILE_HEIGHT
    pox = @pixel_offset_x
    poy = @pixel_offset_y
    bridge_on = $PokemonGlobal.bridge > 0
    $MapFactory.maps.each do |map|
      map_display_x_tile = (map.display_x.to_f / Game_Map::X_SUBPIXELS).round / tw
      map_display_y_tile = (map.display_y.to_f / Game_Map::Y_SUBPIXELS).round / th
      start_x = [-map_display_x_tile, 0].max
      start_y = [-map_display_y_tile, 0].max
      end_x = [cols - 1, map.width - map_display_x_tile - 1].min
      end_y = [rows - 1, map.height - map_display_y_tile - 1].min
      next if start_x > end_x || start_y > end_y || end_x < 0 || end_y < 0
      data = map.data
      (start_x..end_x).each do |i|
        tile_x = i + map_display_x_tile
        col = @tiles[i]
        sx = (((i - ring) * tw - pox) * s).floor
        (start_y..end_y).each do |j|
          tile_y = j + map_display_y_tile
          coord = col[j]
          sy = nil
          3.times do |layer|
            tile = coord[layer]
            tile_id = data[tile_x, tile_y, layer]
            if do_full_refresh || tile.need_refresh || tile.tile_id != tile_id
              refresh_tile(tile, i, j, map, layer, tile_id)
            elsif tile.visible
              refresh_tile_frame(tile, tile_id) if frames && tile.animated
              if moved
                tile.x = sx
                tile.y = (sy ||= (((j - ring) * th - poy) * s).floor)
              end
              if moved_v
                if tile.underwater_tile
                  tile.z = -5
                elsif tile.bridge && bridge_on
                  tile.z = 0
                else
                  pr = tile.priority
                  tile.z = (pr == 0) ? 0 : (((j - ring) * th + pr * 32 + 32) * s).round
                end
              end
            end
          end
          visited[i * rows + j] = true
        end
      end
    end
    # Clear all unvisited tile sprites
    @tiles.each_with_index do |col, i|
      base = i * rows
      col.each_with_index do |coord, j|
        next if visited[base + j]
        coord.each do |tile|
          next if !tile.visible && tile.tile_id == 0   # already clear
          tile.set_bitmap("", 0, false, false, 0, nil)
          tile.shows_reflection = false
          tile.bridge = false
        end
      end
    end
    @need_refresh = false
    @autotiles.changed = false
  end
end

KIF.guard_base("006_Map renderer/001_TilemapRenderer.rb", 1813210744, "TilemapRenderer#update (C-UI-01 MapZoom#mz_zoomed_update)") if KIF.respond_to?(:guard_base)

# Frames drawn in between slide the map by the camera's move, which is drawn smaller
if defined?(KIF::FrameRate) && KIF::FrameRate.respond_to?(:camera_move)
  class << KIF::FrameRate
    alias mz_orig_camera_move camera_move unless method_defined?(:mz_orig_camera_move) || private_method_defined?(:mz_orig_camera_move)

    def camera_move(now, last)
      ret = mz_orig_camera_move(now, last)
      s = KIF::MapZoom.scale
      return ret if !ret || s == 1.0
      return [ret[0] * s, ret[1] * s]
    end
  end
end

#-------------------------------------------------------------------------------
# Camera
#-------------------------------------------------------------------------------
class Game_Map
  alias mz_orig_display_x_set display_x= unless method_defined?(:mz_orig_display_x_set) || private_method_defined?(:mz_orig_display_x_set)
  alias mz_orig_display_y_set display_y= unless method_defined?(:mz_orig_display_y_set) || private_method_defined?(:mz_orig_display_y_set)

  # zoomed, the player's camera does the edge stops (the map's SnapEdges
  # limits are for the normal view)
  def display_x=(value)
    return mz_orig_display_x_set(value) unless KIF::MapZoom.zoomed?
    return if @display_x == value
    @display_x = value
    $MapFactory.setMapsInRange if $MapFactory
  end

  def display_y=(value)
    return mz_orig_display_y_set(value) unless KIF::MapZoom.zoomed?
    return if @display_y == value
    @display_y = value
    $MapFactory.setMapsInRange if $MapFactory
  end
end

class Game_Player
  alias mz_orig_center center unless method_defined?(:mz_orig_center) || private_method_defined?(:mz_orig_center)
  alias mz_orig_isCentered isCentered unless method_defined?(:mz_orig_isCentered) || private_method_defined?(:mz_orig_isCentered)
  alias mz_orig_update_screen_position update_screen_position unless method_defined?(:mz_orig_update_screen_position) || private_method_defined?(:mz_orig_update_screen_position)

  def mz_camera(rx, ry)
    return KIF::MapZoom.clamp(self.map, (rx - KIF::MapZoom.center_x).round, (ry - KIF::MapZoom.center_y).round)
  end

  def center(x, y)
    return mz_orig_center(x, y) unless KIF::MapZoom.zoomed?
    dx, dy = mz_camera(x * Game_Map::REAL_RES_X, y * Game_Map::REAL_RES_Y)
    self.map.display_x = dx
    self.map.display_y = dy
  end

  def isCentered
    return mz_orig_isCentered unless KIF::MapZoom.zoomed?
    dx, dy = mz_camera(x * Game_Map::REAL_RES_X, y * Game_Map::REAL_RES_Y)
    return self.map.display_x == dx && self.map.display_y == dy
  end

  def update_screen_position(last_real_x, last_real_y)
    return mz_orig_update_screen_position(last_real_x, last_real_y) unless KIF::MapZoom.zoomed?
    return if self.map.scrolling? || !(@moved_last_frame || @moved_this_frame)
    dx, dy = mz_camera(@real_x, @real_y)
    self.map.display_x = dx
    self.map.display_y = dy
  end
end

# Connected maps further out are loaded for the larger view
module MapFactoryHelper
  class << self
    alias mz_orig_mapInRange mapInRange? unless method_defined?(:mz_orig_mapInRange) || private_method_defined?(:mz_orig_mapInRange)
    alias mz_orig_mapInRangeById mapInRangeById? unless method_defined?(:mz_orig_mapInRangeById) || private_method_defined?(:mz_orig_mapInRangeById)

    def mapInRange?(map)
      return mz_orig_mapInRange(map) unless KIF::MapZoom.zoomed?
      return mz_in_range?(map.width, map.height, map.display_x, map.display_y)
    end

    def mapInRangeById?(id, dispx, dispy)
      return mz_orig_mapInRangeById(id, dispx, dispy) unless KIF::MapZoom.zoomed?
      dims = getMapDims(id)
      return mz_in_range?(dims[0], dims[1], dispx, dispy)
    end

    # 6.8.2's test (6 tiles round the screen) on the zoomed view
    def mz_in_range?(w, h, dispx, dispy)
      range = 6
      return false if dispx >= (w + range) * Game_Map::REAL_RES_X
      return false if dispy >= (h + range) * Game_Map::REAL_RES_Y
      return false if dispx <= -(KIF::MapZoom.view_w + range * Game_Map::REAL_RES_X)
      return false if dispy <= -(KIF::MapZoom.view_h + range * Game_Map::REAL_RES_Y)
      return true
    end
  end
end

class Scene_Map
  alias mz_orig_updateSpritesets updateSpritesets unless method_defined?(:mz_orig_updateSpritesets) || private_method_defined?(:mz_orig_updateSpritesets)

  def updateSpritesets(refresh = false)
    KIF::MapZoom.sync
    mz_orig_updateSpritesets(refresh)
  end
end

#-------------------------------------------------------------------------------
# Characters
#-------------------------------------------------------------------------------
class Game_Character
  alias mz_orig_screen_x screen_x unless method_defined?(:mz_orig_screen_x) || private_method_defined?(:mz_orig_screen_x)
  alias mz_orig_screen_y_ground screen_y_ground unless method_defined?(:mz_orig_screen_y_ground) || private_method_defined?(:mz_orig_screen_y_ground)
  alias mz_orig_screen_y screen_y unless method_defined?(:mz_orig_screen_y) || private_method_defined?(:mz_orig_screen_y)
  alias mz_orig_screen_z screen_z unless method_defined?(:mz_orig_screen_z) || private_method_defined?(:mz_orig_screen_z)

  def screen_x
    s = KIF::MapZoom.scale
    return mz_orig_screen_x if s == 1.0
    return (mz_orig_screen_x * s).floor   # floor, like the tiles
  end

  def screen_y_ground
    s = KIF::MapZoom.scale
    return mz_orig_screen_y_ground if s == 1.0
    return (mz_orig_screen_y_ground * s).floor
  end

  # 6.8.2 adds the jump height to screen_y_ground: that part is scaled too
  def screen_y
    s = KIF::MapZoom.scale
    return mz_orig_screen_y if s == 1.0
    g = screen_y_ground
    return KIF::MapZoom.toward(g, mz_orig_screen_y, s)
  end

  def screen_z(height = 0)
    s = KIF::MapZoom.scale
    return mz_orig_screen_z(height) if s == 1.0
    return -1 if @under_everything
    return 0 if @under_player
    return 999 if @always_on_top
    return @forced_z if @forced_z
    return 999 if @on_bridge && $PokemonGlobal.bridge <= 0
    z = screen_y_ground
    if @tile_id > 0
      begin
        return z + (self.map.priorities[@tile_id] * 32 * s).round
      rescue
        return 0
      end
    end
    return z + ((height > Game_Map::TILE_HEIGHT) ? ((Game_Map::TILE_HEIGHT - 1) * s).round : 0)
  end
end

class Sprite_Character
  alias mz_orig_update update unless method_defined?(:mz_orig_update) || private_method_defined?(:mz_orig_update)

  # zoom first: the reflection and surf base copy it in the same update
  def update
    s = KIF::MapZoom.scale
    zoom = s != 1.0 || @mz_zoomed
    if zoom
      self.zoom_x = s
      self.zoom_y = s
      @mz_zoomed = (s != 1.0)
    end
    mz_orig_update
    return unless zoom && !disposed?
    # PIF's ground shadow and the quest/talk bubble over NPCs: sized and
    # placed (their offsets from the sprite) like the sprite
    [@shadow, @questIcon].each do |sp|
      next if !sp || sp.disposed?
      sp.zoom_x = s
      sp.zoom_y = s
      sp.y = KIF::MapZoom.toward(self.y, sp.y, s) if s != 1.0
    end
  end
end

# Hair, hats and the bicycle follow the player's size every frame, and their
# offsets from the body shrink with it
class Sprite_Player
  alias mz_orig_update_player update unless method_defined?(:mz_orig_update_player) || private_method_defined?(:mz_orig_update_player)

  def mz_wearables
    return [@hat, @hat2, @hair, @bicycle].map { |w| w && w.sprite }.compact.reject(&:disposed?)
  end

  def update
    mz_orig_update_player
    s = KIF::MapZoom.scale
    mz_wearables.each do |w|
      w.zoom_x = self.zoom_x
      w.zoom_y = self.zoom_y
      next if s == 1.0
      w.x = KIF::MapZoom.toward(self.x, w.x, s)
      w.y = KIF::MapZoom.toward(self.y, w.y, s)
    end
  end
end

class Sprite_Reflection
  alias mz_orig_update update unless method_defined?(:mz_orig_update) || private_method_defined?(:mz_orig_update)

  def update
    mz_orig_update
    s = KIF::MapZoom.scale
    return if s == 1.0 || !@sprite || @sprite.disposed?
    @sprite.x = KIF::MapZoom.toward(@parent_sprite.x, @sprite.x, s)
    @sprite.y = KIF::MapZoom.toward(@parent_sprite.y, @sprite.y, s)
  end
end

class Sprite_SurfBase
  alias mz_orig_update update unless method_defined?(:mz_orig_update) || private_method_defined?(:mz_orig_update)

  def update
    mz_orig_update
    s = KIF::MapZoom.scale
    return if s == 1.0 || !@sprite || @sprite.disposed? || !$PokemonTemp.surfJump
    @sprite.x = (@sprite.x * s).round   # mid surf-jump the base sits on its tile, not under the player
    @sprite.y = (@sprite.y * s).round
  end
end

# Shadows and light effects ask for the character's size here
module ScreenPosHelper
  class << self
    alias mz_orig_pbScreenZoomX pbScreenZoomX unless method_defined?(:mz_orig_pbScreenZoomX) || private_method_defined?(:mz_orig_pbScreenZoomX)
    alias mz_orig_pbScreenZoomY pbScreenZoomY unless method_defined?(:mz_orig_pbScreenZoomY) || private_method_defined?(:mz_orig_pbScreenZoomY)

    def pbScreenZoomX(ch)
      return mz_orig_pbScreenZoomX(ch) * KIF::MapZoom.scale
    end

    def pbScreenZoomY(ch)
      return mz_orig_pbScreenZoomY(ch) * KIF::MapZoom.scale
    end
  end
end

# Grass rustles and other map animations
class AnimationSprite
  alias mz_orig_setCoords setCoords unless method_defined?(:mz_orig_setCoords) || private_method_defined?(:mz_orig_setCoords)

  def setCoords
    mz_orig_setCoords
    s = KIF::MapZoom.scale
    return if s == 1.0
    self.x = (self.x * s).round
    self.y = (self.y * s).round
  end
end

# Animation cells on map sprites (grass rustle, emotes over characters) are
# drawn smaller and closer to their sprite
class SpriteAnimation   # (RPG::Sprite's animation player; @sprite is the sprite it plays on)
  alias mz_orig_animation_set_sprites animation_set_sprites unless method_defined?(:mz_orig_animation_set_sprites) || private_method_defined?(:mz_orig_animation_set_sprites)

  def animation_set_sprites(sprites, cell_data, position, quick_update = false)
    mz_orig_animation_set_sprites(sprites, cell_data, position, quick_update)
    s = KIF::MapZoom.scale
    return if s == 1.0 || position == 3
    return unless @sprite.is_a?(Sprite_Character) || @sprite.is_a?(AnimationSprite)
    sprites.each do |sp|
      next if !sp || sp.disposed? || !sp.visible
      sp.x = KIF::MapZoom.toward(@sprite.x, sp.x, s)
      sp.y = KIF::MapZoom.toward(@sprite.y, sp.y, s)
      next if quick_update   # the zoom was only set (and scaled) on a full update
      sp.zoom_x *= s
      sp.zoom_y *= s
    end
  end
end

#-------------------------------------------------------------------------------
# Fog moves and scales with the map (still covering the whole screen)
#-------------------------------------------------------------------------------
class Spriteset_Map
  alias mz_orig_update update unless method_defined?(:mz_orig_update) || private_method_defined?(:mz_orig_update)

  def update
    mz_orig_update
    s = KIF::MapZoom.scale
    return if s == 1.0
    tmox = (@map.display_x / Game_Map::X_SUBPIXELS).round
    tmoy = (@map.display_y / Game_Map::Y_SUBPIXELS).round
    [[@fog, @map.fog_ox, @map.fog_oy], [@fog2, (@map.fog2_ox rescue 0), (@map.fog2_oy rescue 0)]].each do |f, fx, fy|
      next if !f || f.disposed?
      f.ox = ((tmox + fx) * s).round
      f.oy = ((tmoy + fy) * s).round
      f.zoom_x = @map.fog_zoom / 100.0 * s
      f.zoom_y = @map.fog_zoom / 100.0 * s
    end
  end
end

#-------------------------------------------------------------------------------
# Cave darkness: the lit circle covers the same tiles as at Normal
#-------------------------------------------------------------------------------
class DarknessSprite
  alias mz_orig_refresh refresh unless method_defined?(:mz_orig_refresh) || private_method_defined?(:mz_orig_refresh)

  def refresh
    s = KIF::MapZoom.scale
    return mz_orig_refresh if s == 1.0
    r = @radius
    @radius = (r * s).round
    begin
      mz_orig_refresh
    ensure
      @radius = r
    end
  end
end

class NightmareSprite
  alias mz_orig_refresh refresh unless method_defined?(:mz_orig_refresh) || private_method_defined?(:mz_orig_refresh)

  def refresh
    s = KIF::MapZoom.scale
    return mz_orig_refresh if s == 1.0
    r = @radius
    @radius = (r * s).round
    begin
      mz_orig_refresh
    ensure
      @radius = r
    end
  end
end
