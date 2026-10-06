class CustomSpriteExtracter < PIFSpriteExtracter
  @instance = new
  def self.instance
    @@instance ||= new  # If @@instance is nil, create a new instance
    @@instance           # Return the existing or new instance
  end

  SPRITESHEET_FOLDER_PATH = "Graphics/CustomBattlers/spritesheets/spritesheets_custom/"
  SPRITE_SIZE = 96           # Original sprite size
  SHEET_WIDTH = SPRITE_SIZE * COLUMNS # 2880 pixels wide spritesheet

  def load_bitmap_from_spritesheet(pif_sprite)
    body_id = pif_sprite.body_id
    spritesheet_file = getSpritesheetPath(pif_sprite)
    spritesheet_bitmap = AnimatedBitmap.new(spritesheet_file).bitmap

    sprite_x_position,sprite_y_position  =get_sprite_position_on_spritesheet(body_id,SPRITE_SIZE,COLUMNS)
    src_rect = Rect.new(sprite_x_position, sprite_y_position, SPRITE_SIZE, SPRITE_SIZE)

    sprite_bitmap = Bitmap.new(SPRITE_SIZE, SPRITE_SIZE)
    sprite_bitmap.blt(0, 0, spritesheet_bitmap, src_rect)
    spritesheet_bitmap.dispose  # Dispose since not needed

    return sprite_bitmap
  end

  def load_sprite_to_file(pif_sprite)
    head_id = pif_sprite.head_id
    body_id = pif_sprite.body_id
    alt_letter = pif_sprite.alt_letter
    base_folder = "#{Settings::CUSTOM_BATTLERS_FOLDER_INDEXED}#{head_id}/"

    individualSpriteFile = "#{base_folder}#{head_id}.#{body_id}#{alt_letter}.png"
    if !pbResolveBitmap(individualSpriteFile)
      animatedBitmap = load_sprite_from_spritesheet(pif_sprite)
      Dir.mkdir(base_folder) unless Dir.exist?(base_folder)
      animatedBitmap.bitmap.save_to_png(individualSpriteFile)
    end
    return AnimatedBitmap.new(individualSpriteFile)
  end

  def getSpritesheetPath(pif_sprite)
    alt_letter = pif_sprite.alt_letter
    head_id = pif_sprite.head_id
    return "#{SPRITESHEET_FOLDER_PATH}#{head_id}/#{head_id}#{alt_letter}.png"
  end

  def should_update_spritesheet?(pif_sprite)
    return false if !$updated_spritesheets
    return false if !downloadAllowed?()
    return false if requestRateExceeded?(Settings::CUSTOMSPRITES_RATE_LOG_FILE,Settings::CUSTOMSPRITES_ENTRIES_RATE_TIME_WINDOW,Settings::CUSTOMSPRITES_RATE_MAX_NB_REQUESTS,false)
    spritesheet_file = getSpritesheetPath(pif_sprite)
    return true if !pbResolveBitmap(spritesheet_file)
    return !$updated_spritesheets.include?(spritesheet_file)
  end


  def load_sprite_directly(head_id,body_id,alt_letter="")
    load_sprite(PIFSprite.new(:CUSTOM,head_id,body_id,alt_letter))
  end


  def get_resize_scale
    return 3
  end

  #
  # def extract_bitmap_to_file(head_id, body_id, alt_letter, folder)
  #   # Create the directory if it doesn't exist
  #   Dir.mkdir(folder) unless Dir.exist?(folder)
  #
  #   # Load the entire spritesheet
  #   spritesheet_file = "#{SPRITESHEET_FOLDER_PATH}#{head_id}\\#{head_id}#{alt_letter}.png"
  #   spritesheet_bitmap = AnimatedBitmap.new(spritesheet_file).bitmap
  #
  #   # Calculate the 0-based row and column from the sprite index
  #   index = body_id
  #   row = index / COLUMNS
  #   col = index % COLUMNS
  #
  #   # Define the area of the sprite on the spritesheet
  #   sprite_x_position = col * SPRITE_SIZE
  #   sprite_y_position = row * SPRITE_SIZE
  #
  #   # Create a new bitmap for the sprite at its original size
  #   sprite_bitmap = Bitmap.new(SPRITE_SIZE, SPRITE_SIZE)
  #
  #   # Copy the sprite from the spritesheet to the new bitmap
  #   src_rect = Rect.new(sprite_x_position, sprite_y_position, SPRITE_SIZE, SPRITE_SIZE)
  #   sprite_bitmap.blt(0, 0, spritesheet_bitmap, src_rect)
  #
  #   # Dispose of the spritesheet bitmap if it’s no longer needed
  #   spritesheet_bitmap.dispose
  #
  #   # Save the sprite bitmap to a file
  #   file_path = "#{folder}/#{head_id}.#{body_id}.png"
  #   sprite_bitmap.save_to_png(file_path)
  #
  #   # Dispose of the sprite bitmap
  #   sprite_bitmap.dispose
  #
  #   # Return the path to the saved PNG file
  #   return file_path
  # end

end