def getSecretBaseBiome(terrainTag)
  return :TREE if terrainTag.secretBase_tree
  return :CAVE if terrainTag.secretBase_cave
  return :BUSH if terrainTag.secretBase_bush
  # todo: other types
  return nil
end

def pickSecretBaseLayout(baseType)
  mapId = MAP_SECRET_BASES
  # Distance is how far away the same coordinates will share the same seed
  case baseType
  when :TREE
    distance = 2
  else
    distance = 4
  end
  # Snap to 2x2 blocks
  block_x = $game_player.x / distance
  block_y = $game_player.y / distance

  # Universal deterministic seed
  seed_str = "#{baseType}-#{mapId}-#{block_x}-#{block_y}"
  seed = Zlib.crc32(seed_str)

  rng = Random.new(seed)
  layoutType = weighted_sample(SecretBasesData::SECRET_BASE_ENTRANCES, rng)
  return layoutType
end

def weighted_sample(entries, rng)
  total = entries.values.sum { |v| v[:rareness] }
  pick  = rng.rand * total
  entries.each do |key, v|
    return key if (pick -= v[:rareness]) <= 0
  end
  # Fallback: return the last key
  return entries.keys.last
end


def pbSecretBase(biome_type, base_layout_type)
  base_map_id = MAP_SECRET_BASES
  player_map_id = $game_map.map_id
  player_position = [$game_player.x, $game_player.y]

  if secretBaseExistsAtPosition(player_map_id, player_position)
    enterSecretBase
  else
    # Todo: Determine the secret base's map ids and coordinates from a seed using the current map and the base type instead of passing it manually.
    createSecretBaseHere(biome_type, base_map_id, base_layout_type)
  end
end

def secretBaseExistsAtPosition(map_id, position)
  return false unless $Trainer.secretBase
  current_outdoor_id = $Trainer.secretBase.outside_map_id
  current_outdoor_coordinates = $Trainer.secretBase.outside_entrance_position
  return current_outdoor_id == map_id && current_outdoor_coordinates == position
end

def createSecretBaseHere(biomeType, secretBaseMap = 0, baseLayoutType = :TYPE_1)
  if pbConfirmMessage(_INTL("Do you want to create a new secret base here?"))
    if $Trainer.secretBase
      unless pbConfirmMessage(_INTL("This will overwrite your current secret base. Do you still wish to continue?"))
        return
      end
    end
    current_map_id = $game_map.map_id
    current_position = [$game_player.x, $game_player.y]
    $Trainer.secretBase = initialize_player_secret_base(biomeType, current_map_id, current_position, secretBaseMap, baseLayoutType)
    setupAllSecretBaseEntrances
  end
end

def initialize_player_secret_base(biome_type, outside_map_id, outside_position, base_map_id, layout_shape)
  return SecretBase.new(
    biome: biome_type,
    outside_map_id: outside_map_id,
    outside_entrance_position: outside_position,
    inside_map_id: base_map_id,
    base_layout_type: layout_shape,
    is_visitor: false
  )
end

#For when called from Scene_Map
def placeFurnitureMenu
  controller = getSecretBaseController
  controller.placeFurnitureMenu
end


def rotate_held_furniture_right
  return unless $game_temp.moving_furniture
  pbSEPlay("GUI party switch", 80, 100)
  directionFix = $game_player.direction_fix
  $game_player.direction_fix = false
  $game_player.turn_right_90
  $game_player.direction_fix=directionFix
end
def rotate__held_furniture_left
  return unless $game_temp.moving_furniture
  pbSEPlay("GUI party switch", 80, 100)
  directionFix = $game_player.direction_fix
  $game_player.direction_fix = false
  $game_player.turn_left_90
  $game_player.direction_fix=directionFix
end


def exitSecretBase()
  controller = getSecretBaseController
  return if controller&.isMovingFurniture?
  pbStartOver if !$Trainer.secretBase || !$Trainer.secretBase.outside_map_id || !$Trainer.secretBase.outside_entrance_position
  # Should never happen, but just in case
  enteredSecretBase = getEnteredSecretBase
  if enteredSecretBase && enteredSecretBase.is_a?(SecretBase)
    outdoor_id = enteredSecretBase.outside_map_id
    outdoor_coordinates = enteredSecretBase.outside_entrance_position
  else
    #Fallback on player's base
    outdoor_id = $Trainer.secretBase.outside_map_id
    outdoor_coordinates = $Trainer.secretBase.outside_entrance_position
  end


  $PokemonTemp.pbClearTempEvents
  pbFadeOutIn {
    $game_temp.player_new_map_id = outdoor_id
    $game_temp.player_new_x = outdoor_coordinates[0]
    $game_temp.player_new_y = outdoor_coordinates[1]
    $scene.transfer_player(true)
    $game_map.autoplay
    $game_map.refresh
  }
  $PokemonTemp.pbClearTempEvents
  $PokemonTemp.enteredSecretBaseController=nil
  setupAllSecretBaseEntrances
end

def enterSecretBase()
  event = $game_map.events[@event_id]
  return if event.nil?
  if event.variable && event.variable.is_a?(SecretBase)
    secretBase = event.variable
  else
    secretBase= $Trainer.secretBase
  end
  controller = SecretBaseController.new(secretBase)
  $PokemonTemp.enteredSecretBaseController = controller

  return unless secretBase.is_a?(SecretBase)
  $PokemonTemp.pbClearTempEvents
  pbFadeOutIn {
    $game_temp.player_new_map_id = MAP_SECRET_BASES
    $game_temp.player_new_x = secretBase.inside_entrance_position[0]
    $game_temp.player_new_y = secretBase.inside_entrance_position[1]
    $scene.transfer_player(true)
    $game_map.autoplay
    SecretBaseLoader.new.loadSecretBaseFurniture(secretBase)
    $game_map.refresh
  }

end
def obtain_all_decorations
  $Trainer.owned_decorations = [] unless $Trainer.owned_decorations
  SecretBasesData::SECRET_BASE_ITEMS.keys.each do |item_id|
    obtain_decoration_silent(item_id)
  end
end
def obtain_decoration(item_id)
  $Trainer.owned_decorations = [] unless $Trainer.owned_decorations
  if SecretBasesData::SECRET_BASE_ITEMS[item_id]
    obtainDecorationMessage(item_id)
    $Trainer.owned_decorations << item_id
  end
end


def obtain_decoration_silent(item_id)
  $Trainer.owned_decorations = [] unless $Trainer.owned_decorations
  if SecretBasesData::SECRET_BASE_ITEMS[item_id]
    $Trainer.owned_decorations << item_id
  end
end

def give_starting_decorations
  furniture = [
    :PLANT,:RED_CHAIR
  ]
  obtain_decoration_silent(:PC)
  furniture.each do |item|
    obtain_decoration(item)
  end
end


def obtainDecorationMessage(item_id)
  decoration = SecretBasesData::SECRET_BASE_ITEMS[item_id]
  pictureViewport = showDecorationPicture(item_id)
  musical_effect = "Key item get"
  pbMessage(_INTL("\\me[{1}]You obtained a \\c[1]{2}\\c[0]!", musical_effect, decoration.real_name))
  pictureViewport.dispose if pictureViewport
end

def showDecorationPicture(item_id)
  begin
    decoration = SecretBasesData::SECRET_BASE_ITEMS[item_id]
    path = "Graphics/Characters/player/secretBases/#{decoration.graphics}"

    viewport = Viewport.new(Graphics.width / 4, 0, Graphics.width / 2, Graphics.height)
    bg_sprite = Sprite.new(viewport)
    decoration_sprite = Sprite.new(viewport)

    echoln path
    echoln pbResolveBitmap(path)

    if pbResolveBitmap(path)
      sheet = Bitmap.new(path)

      # Character sheets are 4x4
      frame_width  = sheet.width / 4
      frame_height = sheet.height / 4

      # First frame = top-left corner (row 0, col 0)
      rect = Rect.new(0, 0, frame_width, frame_height)

      # Copy that frame into its own bitmap
      cropped = Bitmap.new(frame_width, frame_height)
      cropped.blt(0, 0, sheet, rect)

      decoration_sprite.bitmap = cropped
    end

    bg_bitmap = AnimatedBitmap.new("Graphics/Pictures/Outfits/obtain_bg")
    bg_sprite.bitmap = bg_bitmap.bitmap

    decoration_sprite.x = 92
    decoration_sprite.y = 50
    decoration_sprite.zoom_x = 2
    decoration_sprite.zoom_y = 2

    bg_sprite.x = 0
    viewport.z = 99999

    return viewport
  rescue
  end
end


