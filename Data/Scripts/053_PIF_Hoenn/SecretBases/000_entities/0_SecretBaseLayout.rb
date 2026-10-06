class SecretBaseLayout
  attr_accessor :items  #SecretBaseItemInstance
  attr_accessor :tileset #todo Reuse the same layouts map for all bases and change the tileset depending on the type
  attr_accessor :biome_type #:TREES, :CLIFF, :CLIFF_BEACH, :BUSH, etc. -> Determines which tiles are used in the base
  attr_accessor :is_player_base
  def initialize(layout_biome,is_player_base=false)
    @biome_type = layout_biome
    @items = []
    @is_player_base = is_player_base
  end

  def add_item(itemId, position = [0, 0])
    new_item = SecretBaseItemInstance.new(itemId, position)
    @items << new_item
    return new_item.instanceId
  end

  def get_item_at_position(position = [0,0])
    @items.each do |item|
      return item if item.get_occupied_positions.include?(position)
    end
    return nil
  end

  def get_item_by_id(instanceId)
    @items.each do |item|
      return item if item.instanceId == instanceId
    end
    return nil
  end


  def remove_item_by_instance(instanceId)
    @items.each do |item|
      if item.instanceId == instanceId
        @items.delete(item)
      end
    end
    return nil
  end

  def remove_item_at_position(position = [0, 0])
    @items.each do |item|
      if item.position == position
        @items.delete(item)
      end
    end
  end

  # returns a list of ids of the items that are currently in the base's layout
  def list_items_instances()
    list = []
    @items.each do |item|
      list << item.instanceId
    end
  end

  def get_all_occupied_positions()
    occupied_positions = []
    @items.each do |item|
      occupied_positions << get_occupied_positions_for_item(item)
    end
    return occupied_positions
  end




  def check_position_available_for_item(itemInstance,position)
    #placed_item_positions = get_all_occupied_positions
    item_occupied_positions = itemInstance.calculate_occupied_volume_positions(position)
    item_occupied_positions.each do |position|
      x, y = position
      #return false if placed_item_positions.include?(position)
      return false if !$game_map.passableStrict?(x, y, DIRECTION_ALL)
    end
    return true
  end


end