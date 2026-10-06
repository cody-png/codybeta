class BaseSpriteExtracter < PIFSpriteExtracter
  @instance = new

  def self.instance
    @@instance ||= new # If @@instance is nil, create a new instance
    @@instance # Return the existing or new instance
  end

  SPRITESHEET_FOLDER_PATH = "Graphics/CustomBattlers/spritesheets/spritesheets_base/"
  SPRITE_SIZE = 96 # Original sprite size
  NB_COLUMNS_BASESPRITES = 10
  SHEET_WIDTH = SPRITE_SIZE * NB_COLUMNS_BASESPRITES # 2880 pixels wide spritesheet
  def load_bitmap_from_spritesheet(pif_sprite)
    alt_letter = pif_sprite.alt_letter
    spritesheet_file = getSpritesheetPath(pif_sprite)
    spritesheet_bitmap = AnimatedBitmap.new(spritesheet_file).bitmap

    letter_index = letters_to_index(alt_letter)
    sprite_x_position, sprite_y_position = get_sprite_position_on_spritesheet(letter_index, SPRITE_SIZE, NB_COLUMNS_BASESPRITES)
    src_rect = Rect.new(sprite_x_position, sprite_y_position, SPRITE_SIZE, SPRITE_SIZE)

    sprite_bitmap = Bitmap.new(SPRITE_SIZE, SPRITE_SIZE)
    sprite_bitmap.blt(0, 0, spritesheet_bitmap, src_rect)
    spritesheet_bitmap.dispose # Dispose since not needed

    return sprite_bitmap
  end

  def letters_to_index(letters)
    letters = letters.downcase # Ensure input is case-insensitive
    index = 0
    letters.each_char do |char|
      index = index * 26 + (char.ord - 'a'.ord + 1)
    end
    #echoln "index: #{index}"
    return index
  end

  def load_sprite_directly(head_id, body_id, alt_letter = "")
    load_sprite(PIFSprite.new(:CUSTOM, head_id, body_id, alt_letter))
  end

  def getSpritesheetPath(pif_sprite)
    dex_number = getDexNumberForSpecies(pif_sprite.head_id)
    return "#{SPRITESHEET_FOLDER_PATH}#{dex_number}.png"
  end

  def should_update_spritesheet?(pif_sprite)
    return false if !$updated_spritesheets
    return false if !downloadAllowed?()
    return false if requestRateExceeded?(Settings::CUSTOMSPRITES_RATE_LOG_FILE,Settings::CUSTOMSPRITES_ENTRIES_RATE_TIME_WINDOW,Settings::CUSTOMSPRITES_RATE_MAX_NB_REQUESTS,false)
    spritesheet_file = getSpritesheetPath(pif_sprite)
    return true if !pbResolveBitmap(spritesheet_file)

    return !$updated_spritesheets.include?(spritesheet_file)
  end

  def get_resize_scale
    return 3
  end
end