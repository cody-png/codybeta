class PokemonStorage
  def pbDeleteMulti(box, indexes)
    for index in indexes
      self[box, index] = nil
    end
    self.party.compact! if box == -1
  end

  def pbStoreBatch(pokemon_positions_array, box_index = @currentBox, cursor_x = 0, cursor_y = 0)
    return -1 if invalid_input?(pokemon_positions_array, box_index)

    box_width  = PokemonBox::BOX_WIDTH
    box_height = PokemonBox::BOX_HEIGHT
    coords     = all_coords(box_width, box_height)

    assignments, unplaced, intended = initialize_assignments(pokemon_positions_array.length)

    spiral = spiral_offsets

    # Phase 1: Lock in guaranteed spots
    lock_guaranteed_spots(pokemon_positions_array, box_index, cursor_x, cursor_y, box_width, box_height,
                          assignments, unplaced, intended)

    available_coords = filter_available_coords(coords, box_index, box_width, assignments)
    return :CANT_PLACE if available_coords.length < unplaced.length

    # Phase 2: Assign leftovers using spiral fallback
    assign_fallback_positions(unplaced, intended, assignments, available_coords, box_width, box_height, cursor_x, cursor_y, spiral)
    return :CANT_PLACE if assignments.compact.uniq.length < assignments.compact.length

    # Phase 3: Commit placements
    commit_assignments(assignments, pokemon_positions_array, box_index, box_width)

    unplaced.empty? ? :PLACED_ALL_FREE : :PLACED_OCCUPIED
  end

  # -----------------------------
  # Helper methods
  # -----------------------------
  def invalid_input?(arr, box_index)
    arr.nil? || arr.empty? || self[box_index].is_a?(StorageTransferBox)
  end

  def all_coords(box_width, box_height)
    (0...box_height).flat_map { |y| (0...box_width).map { |x| [x, y] } }
  end

  def initialize_assignments(length)
    [Array.new(length), [], []] # assignments, unplaced, intended
  end

  def spiral_offsets
    [[0,0],[1,0],[0,1],[-1,0],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1],[2,0],[0,2],[-2,0],[0,-2]]
  end

  def lock_guaranteed_spots(pokemon_positions_array, box_index, cursor_x, cursor_y, box_width, box_height, assignments, unplaced, intended)
    pokemon_positions_array.each_with_index do |pk_data, i|
      rel_x, rel_y = pk_data[1], pk_data[2]
      target_x, target_y = cursor_x + rel_x, cursor_y + rel_y
      intended[i] = [target_x, target_y]

      if target_x.between?(0, box_width-1) && target_y.between?(0, box_height-1)
        index = target_y * box_width + target_x
        assignments[i] = [target_x, target_y] if self[box_index, index].nil?
        unplaced << i if assignments[i].nil?
      else
        unplaced << i
      end
    end
  end

  def filter_available_coords(coords, box_index, box_width, assignments)
    used_coords = assignments.compact
    coords.reject { |cx, cy| !self[box_index, cy * box_width + cx].nil? || used_coords.include?([cx, cy]) }
  end

  def assign_fallback_positions(unplaced, intended, assignments, available_coords, box_width, box_height, cursor_x, cursor_y, spiral)
    unplaced.each_with_index do |i, idx|
      tx, ty = intended[i] || [cursor_x, cursor_y]
      chosen = spiral.map { |offx, offy| [tx + offx, ty + offy] }
                     .find { |nx, ny| nx.between?(0, box_width-1) && ny.between?(0, box_height-1) && available_coords.include?([nx, ny]) }
      chosen ||= available_coords.min_by { |cx, cy| (cx - tx).abs + (cy - ty).abs }
      raise :CANT_PLACE unless chosen
      assignments[i] = chosen
      available_coords.delete(chosen)
    end
  end

  def commit_assignments(assignments, pokemon_positions_array, box_index, box_width)
    assignments.each_with_index do |coords, i|
      next unless coords
      cx, cy = coords
      index = cy * box_width + cx
      if self[box_index, index].nil?
        self[box_index, index] = pokemon_positions_array[i][0]
      else
        rollback(assignments, pokemon_positions_array, box_index, box_width)
        raise :CANT_PLACE
      end
    end
  end

  def rollback(assignments, pokemon_positions_array, box_index, box_width)
    assignments.each do |coords|
      next unless coords
      rx, ry = coords
      rindex = ry * box_width + rx
      self[box_index, rindex] = nil if pokemon_positions_array.any? { |pk| pk[0] == self[box_index, rindex] }
    end
  end


end

