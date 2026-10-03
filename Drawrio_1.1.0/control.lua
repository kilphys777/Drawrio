local ERASE_RADIUS  = 0.8
local CLOSE_RADIUS  = 0.8
local MIN_STEP      = 0.2
local DOT_RADIUS    = 0.4

local DEFAULT_WIDTH = 24
local MIN_WIDTH     = 4
local MAX_WIDTH     = 64

local COLORS = {
  { name = "red",    rgb = { 1, 0.15, 0.15 } },
  { name = "orange", rgb = { 1, 0.55, 0 } },
  { name = "yellow", rgb = { 1, 0.95, 0.1 } },
  { name = "green",  rgb = { 0.2, 0.85, 0.2 } },
  { name = "blue",   rgb = { 0.25, 0.45, 1 } },
  { name = "purple", rgb = { 0.65, 0.3, 0.95 } },
  { name = "white",  rgb = { 1, 1, 1 } },
}

local function init()
  storage.segs       = storage.segs       or {}
  storage.chain      = storage.chain      or {}
  storage.on         = storage.on         or {}
  storage.color      = storage.color      or {}
  storage.width      = storage.width      or {}
  storage.next_group = storage.next_group or 0
end
script.on_init(init)

local function in_world(player)
  return player.render_mode == defines.render_mode.game
end

local function dist(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function dist_to_segment(p, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  local t = 0
  if len2 > 0 then
    t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    t = math.max(0, math.min(1, t))
  end
  return dist(p, { x = a.x + t * dx, y = a.y + t * dy })
end

local function new_group()
  storage.next_group = storage.next_group + 1
  return storage.next_group
end

local function width_of(i)
  return storage.width[i] or DEFAULT_WIDTH
end

local function add_seg(surface, from, to, rgb, group, width)
  local obj = rendering.draw_line{
    color = rgb, width = width, from = from, to = to,
    surface = surface, draw_on_ground = false,
  }
  table.insert(storage.segs, {
    from = from, to = to, obj = obj, surface = surface.index,
    group = group, width = width,
  })
end

local function remove_group(group)
  for n = #storage.segs, 1, -1 do
    local s = storage.segs[n]
    if s.group == group then
      if s.obj.valid then s.obj.destroy() end
      table.remove(storage.segs, n)
    end
  end
end

local function end_chain(i)
  local chain = storage.chain[i]
  if chain and chain.marker and chain.marker.valid then
    chain.marker.destroy()
  end
  storage.chain[i] = nil
end

local function squarish(pts)
  local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(pts) do
    minx, maxx = math.min(minx, p.x), math.max(maxx, p.x)
    miny, maxy = math.min(miny, p.y), math.max(maxy, p.y)
  end
  local w, h = maxx - minx, maxy - miny
  if w < 1 or h < 1 then return nil end
  local ratio = w / h
  if ratio < 0.7 or ratio > 1.4 then return nil end
  local tol = 0.3 * math.max(w, h)
  for _, p in ipairs(pts) do
    local dx = math.min(math.abs(p.x - minx), math.abs(p.x - maxx))
    local dy = math.min(math.abs(p.y - miny), math.abs(p.y - maxy))
    if dx > tol or dy > tol then return nil end
  end
  return { minx = minx, maxx = maxx, miny = miny, maxy = maxy }
end

local SHOW_PANEL = "show_panel"
local SHOW_PANEL_X, SHOW_PANEL_Y = 100, 40

local function show_panel(player)
  if player.gui.screen[SHOW_PANEL] then return end
  local frame = player.gui.screen.add{
    type = "frame", name = SHOW_PANEL, caption = "SIZE", direction = "vertical",
  }
  frame.location = { SHOW_PANEL_X, SHOW_PANEL_Y }

  local row = frame.add{ type = "flow", direction = "horizontal" }
  local slider = row.add{
    type = "slider", name = "width_slider",
    minimum_value = MIN_WIDTH, maximum_value = MAX_WIDTH,
    value = width_of(player.index),
    value_step = 2, discrete_slider = true, discrete_values = true,
  }
  slider.style.width = 160
  row.add{ type = "label", name = "width_label",
           caption = tostring(width_of(player.index)) }
end

local function hide_panel(player)
  local panel = player.gui.screen[SHOW_PANEL]
  if panel then panel.destroy() end
end

script.on_event(defines.events.on_gui_value_changed, function(e)
  if e.element.name ~= "width_slider" then return end
  init()
  local w = math.floor(e.element.slider_value)
  storage.width[e.player_index] = w
  e.element.parent["width_label"].caption = tostring(w)
end)

local COLOR_PANEL = "color_panel"
local COLOR_PANEL_X, COLOR_PANEL_Y = 20, 50

local function show_color_panel(player)
  if player.gui.screen[COLOR_PANEL] then return end
  local frame = player.gui.screen.add{
    type = "frame", name = COLOR_PANEL, direction = "horizontal",
  }
  frame.location = { COLOR_PANEL_X, COLOR_PANEL_Y }
  frame.style.vertical_align = "center"

  local swatch = frame.add{
    type = "progressbar", name = "color_swatch", value = 1,
  }
  swatch.style.bar_width = 32
  swatch.style.width = 32
  swatch.style.color = COLORS[storage.color[player.index] or 1].rgb
end

local function hide_color_panel(player)
  local panel = player.gui.screen[COLOR_PANEL]
  if panel then panel.destroy() end
end

local function refresh_color_panel(player)
  local panel = player.gui.screen[COLOR_PANEL]
  if not panel then return end
  panel["color_swatch"].style.color = COLORS[storage.color[player.index] or 1].rgb
end

local function clear_mod_windows(player)
  for _, child in pairs(player.gui.screen.children) do
    if child.valid and child.get_mod() == script.mod_name then
      child.destroy()
    end
  end
end

local function reset_ui(player)
  clear_mod_windows(player)
  storage.on[player.index] = false
  end_chain(player.index)
end

script.on_event(defines.events.on_singleplayer_init, function()
  init()
  for _, player in pairs(game.players) do reset_ui(player) end
end)

script.on_event(defines.events.on_player_joined_game, function(e)
  init()
  reset_ui(game.get_player(e.player_index))
end)

script.on_configuration_changed(function()
  init()
  for _, player in pairs(game.players) do reset_ui(player) end
end)

script.on_event("pen", function(e)
  init()
  local i = e.player_index
  local player = game.get_player(i)
  storage.on[i] = not storage.on[i]
  end_chain(i)
  if storage.on[i] then
    clear_mod_windows(player)
    show_panel(player)
    show_color_panel(player)
  else
    hide_panel(player)
    hide_color_panel(player)
  end
  player.print(storage.on[i] and "DRAW ON" or "DRAW OFF")
end)

script.on_event("color", function(e)
  init()
  local i = e.player_index
  storage.color[i] = ((storage.color[i] or 1) % #COLORS) + 1
  game.get_player(i).print("USING: " .. COLORS[storage.color[i]].name)
  refresh_color_panel(game.get_player(i))
end)

script.on_event("click", function(e)
  init()
  local i = e.player_index
  local player = game.get_player(i)
  if not storage.on[i] or not in_world(player) then return end

  local p = { x = e.cursor_position.x, y = e.cursor_position.y }
  local rgb = COLORS[storage.color[i] or 1].rgb
  local width = width_of(i)
  local chain = storage.chain[i]

  if chain and chain.surface ~= player.surface.index then
    end_chain(i)
    chain = nil
  end

  if not chain then
    storage.chain[i] = {
      points = { p },
      groups = {},
      surface = player.surface.index,
      marker = rendering.draw_circle{
        color = rgb, radius = math.max(DOT_RADIUS, width / 64), filled = true,
        target = p, surface = player.surface, draw_on_ground = false,
      },
    }
    return
  end

  local last = chain.points[#chain.points]
  if dist(p, last) < MIN_STEP then return end

  if #chain.points == 4 and dist(p, chain.points[1]) <= CLOSE_RADIUS then
    local box = squarish(chain.points)
    if box then
      for _, g in ipairs(chain.groups) do remove_group(g) end
      local side = ((box.maxx - box.minx) + (box.maxy - box.miny)) / 2
      local cx, cy = (box.minx + box.maxx) / 2, (box.miny + box.maxy) / 2
      local h = side / 2
      local c = {
        { x = cx - h, y = cy - h }, { x = cx + h, y = cy - h },
        { x = cx + h, y = cy + h }, { x = cx - h, y = cy + h },
      }
      local g = new_group()
      for k = 1, 4 do
        add_seg(player.surface, c[k], c[k % 4 + 1], rgb, g, width)
      end
      end_chain(i)
      return
    end
  end

  local g = new_group()
  add_seg(player.surface, last, p, rgb, g, width)
  table.insert(chain.groups, g)
  table.insert(chain.points, p)
end)

script.on_event("erase", function(e)
  init()
  local i = e.player_index
  local player = game.get_player(i)
  if not storage.on[i] or not in_world(player) then return end

  end_chain(i)
  local p = e.cursor_position
  for n = #storage.segs, 1, -1 do
    local s = storage.segs[n]
    if not s.obj.valid then
      table.remove(storage.segs, n)
    elseif s.surface == player.surface.index
       and dist_to_segment(p, s.from, s.to)
           <= math.max(ERASE_RADIUS, (s.width or DEFAULT_WIDTH) / 64) then
      remove_group(s.group)
      break
    end
  end
end)