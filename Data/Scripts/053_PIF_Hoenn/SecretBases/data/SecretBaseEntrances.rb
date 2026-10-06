TEMPLATE_EVENT_SECRET_BASE_ENTRANCE_TREE = 4
TEMPLATE_EVENT_SECRET_BASE_ENTRANCE_CAVE = 5
TEMPLATE_EVENT_SECRET_BASE_ENTRANCE_BUSH = 6

module SecretBasesData
  # rareness: The higher, the more common
  SECRET_BASE_ENTRANCES = {
    :TYPE_SMALL_1 => { position: [8, 12], rareness: 1 },
    :TYPE_SMALL_2 => { position: [35, 12], rareness: 1 },
    :TYPE_SMALL_3 => { position: [55, 12], rareness: 1 },
    :TYPE_SMALL_4 => { position: [75, 12], rareness: 1 },
    :TYPE_SMALL_5 => { position: [101, 12], rareness: 1 },
    :TYPE_SMALL_6 => { position: [124, 12], rareness: 1 },
    :TYPE_SMALL_7 => { position: [12, 122], rareness: 1 },
    :TYPE_SMALL_8 => { position: [36, 121], rareness: 1 },
    :TYPE_SMALL_9 => { position: [65, 121], rareness: 1 },
    :TYPE_SMALL_10 => { position: [94, 123], rareness: 1 },
    :TYPE_SMALL_11 => { position: [121, 124], rareness: 1 },

    :TYPE_WIDE_1 => { position: [11, 34], rareness: 0.3 },
    :TYPE_WIDE_2 => { position: [43, 34], rareness: 0.2 },
    :TYPE_WIDE_3 => { position: [72, 34], rareness: 0.2 },
    :TYPE_WIDE_4 => { position: [106, 34], rareness: 0.2 },

    :TYPE_TALL_1 => { position: [7, 71], rareness: 0.3 },
    :TYPE_TALL_2 => { position: [31, 71], rareness: 0.2 },
    :TYPE_TALL_3 => { position: [53, 71], rareness: 0.2 },
    :TYPE_TALL_4 => { position: [85, 71], rareness: 0.2 },
    :TYPE_TALL_5 => { position: [109, 71], rareness: 0.2 },

    :TYPE_SPECIAL_1 => { position: [11, 98], rareness: 0.05 },
    :TYPE_SPECIAL_2 => { position: [40, 97], rareness: 0.05 },
    :TYPE_SPECIAL_3 => { position: [68, 98], rareness: 0.05 },
    :TYPE_SPECIAL_4 => { position: [92, 99], rareness: 0.05 },
  }

end

