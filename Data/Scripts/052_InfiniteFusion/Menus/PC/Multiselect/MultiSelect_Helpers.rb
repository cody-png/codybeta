# selection_helpers.rb (can be split into separate file)
module SelectionConstants
  BOX_NAME = -1
  PARTY = -2
  CLOSE = -3
  PREV_BOX = -4
  NEXT_BOX = -5
end

module SelectionHelper
  # Compute visual selection rectangle. Returns a Rect or nil.
  def self.compute_rect(scene, screen, box, selected)
    return nil unless screen.multiSelectRange

    displayRect = Rect.new(0, 0, 1, 1)
    if box == SelectionConstants::BOX_NAME
      xvalues = []
      yvalues = []
      for i in 0...Settings::MAX_PARTY_SIZE
        xvalues << scene.sprites["boxparty"].x + 18 + 72 * (i % 2)
        yvalues << scene.sprites["boxparty"].y + 2 + 16 * (i % 2) + 64 * (i / 2)
      end
      indexes = screen.getMultiSelection(box, selected)
      # defensive: if indexes empty, return nil
      return nil if indexes.nil? || indexes.empty?
      minx = xvalues[indexes[0]]
      miny = yvalues[indexes[0]] + 16
      maxx = xvalues[indexes[indexes.length - 1]] + 72 - 8
      maxy = yvalues[indexes[indexes.length - 1]] + 64
      displayRect.set(minx, miny, maxx - minx, maxy - miny)
    else
      indexRect = screen.getSelectionRect(box, selected)
      return nil if indexRect.nil?
      displayRect.x = scene.sprites["box"].x + 10 + (48 * indexRect.x)
      displayRect.y = scene.sprites["box"].y + 30 + (48 * indexRect.y) + 16
      displayRect.width = indexRect.width * 48 + 16
      displayRect.height = indexRect.height * 48
    end
    displayRect
  end
end

module SelectionNavigator
  include SelectionConstants

  # Navigate general box grid (supports wrap & special indices)
  def self.navigate_box(key, selection, screen)
    case key
    when Input::UP
      if screen.multiSelectRange
        selection -= PokemonBox::BOX_WIDTH
        selection += PokemonBox::BOX_SIZE if selection < 0
      elsif selection == BOX_NAME
        selection = PARTY
      elsif selection == PARTY
        selection = PokemonBox::BOX_SIZE - 1 - PokemonBox::BOX_WIDTH * 2 / 3
      elsif selection == CLOSE
        selection = PokemonBox::BOX_SIZE - PokemonBox::BOX_WIDTH / 3
      else
        selection -= PokemonBox::BOX_WIDTH
        selection = BOX_NAME if selection < 0
      end
    when Input::DOWN
      if screen.multiSelectRange
        selection += PokemonBox::BOX_WIDTH
        selection -= PokemonBox::BOX_SIZE if selection >= PokemonBox::BOX_SIZE
      elsif selection == BOX_NAME
        selection = PokemonBox::BOX_WIDTH / 3
      elsif selection == PARTY
        selection = BOX_NAME
      elsif selection == CLOSE
        selection = BOX_NAME
      else
        selection += PokemonBox::BOX_WIDTH
        if selection >= PokemonBox::BOX_SIZE
          if selection < PokemonBox::BOX_SIZE + PokemonBox::BOX_WIDTH / 2
            selection = PARTY
          else
            selection = CLOSE
          end
        end
      end
    when Input::LEFT
      if screen.multiSelectRange
        if (selection % PokemonBox::BOX_WIDTH) == 0
          selection += PokemonBox::BOX_WIDTH - 1
        else
          selection -= 1
        end
      elsif selection == BOX_NAME
        selection = PREV_BOX
      elsif selection == PARTY
        selection = CLOSE
      elsif selection == CLOSE
        selection = PARTY
      elsif (selection % PokemonBox::BOX_WIDTH) == 0
        selection += PokemonBox::BOX_WIDTH - 1
      else
        selection -= 1
      end
    when Input::RIGHT
      if screen.multiSelectRange
        if (selection % PokemonBox::BOX_WIDTH) == PokemonBox::BOX_WIDTH - 1
          selection -= PokemonBox::BOX_WIDTH - 1
        else
          selection += 1
        end
      elsif selection == BOX_NAME
        selection = NEXT_BOX
      elsif selection == PARTY
        selection = CLOSE
      elsif selection == CLOSE
        selection = PARTY
      elsif (selection % PokemonBox::BOX_WIDTH) == PokemonBox::BOX_WIDTH - 1
        selection -= PokemonBox::BOX_WIDTH - 1
      else
        selection += 1
      end
    end
    selection
  end

  # Navigate party (left/right/up/down)
  def self.navigate_party(key, selection, screen)
    maxIndex = screen.multiSelectRange ? Settings::MAX_PARTY_SIZE - 1 : Settings::MAX_PARTY_SIZE
    case key
    when Input::LEFT
      selection -= 1
      selection = maxIndex if selection < 0
    when Input::RIGHT
      selection += 1
      selection = 0 if selection > maxIndex
    when Input::UP
      if selection == Settings::MAX_PARTY_SIZE
        selection = Settings::MAX_PARTY_SIZE - 1
      else
        selection -= 2
        selection = selection % Settings::MAX_PARTY_SIZE if screen.multiSelectRange
        selection = maxIndex if selection < 0
      end
    when Input::DOWN
      if selection == Settings::MAX_PARTY_SIZE
        selection = 0
      else
        selection += 2
        selection = selection % Settings::MAX_PARTY_SIZE if screen.multiSelectRange
        selection = maxIndex if selection > maxIndex
      end
    end
    selection
  end
end
