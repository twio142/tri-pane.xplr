---@diagnostic disable
local xplr = xplr
---@diagnostic enable

local no_color = os.getenv("NO_COLOR")

local function green(x)
  if no_color == nil then
    return "\x1b[32m" .. x .. "\x1b[0m"
  else
    return x
  end
end

local function yellow(x)
  if no_color == nil then
    return "\x1b[33m" .. x .. "\x1b[0m"
  else
    return x
  end
end

local function red(x)
  if no_color == nil then
    return "\x1b[31m" .. x .. "\x1b[0m"
  else
    return x
  end
end

local function bit(x, color, cond)
  if cond then
    return color(x)
  else
    return color("-")
  end
end

local function datetime(num)
  return tostring(os.date("%a %b %d %H:%M:%S %Y", num / 1000000000))
end

local function permissions(p)
  local r = ""

  r = r .. bit("r", green, p.user_read)
  r = r .. bit("w", yellow, p.user_write)

  if p.user_execute == false and p.setuid == false then
    r = r .. bit("-", red, p.user_execute)
  elseif p.user_execute == true and p.setuid == false then
    r = r .. bit("x", red, p.user_execute)
  elseif p.user_execute == false and p.setuid == true then
    r = r .. bit("S", red, p.user_execute)
  else
    r = r .. bit("s", red, p.user_execute)
  end

  r = r .. bit("r", green, p.group_read)
  r = r .. bit("w", yellow, p.group_write)

  if p.group_execute == false and p.setuid == false then
    r = r .. bit("-", red, p.group_execute)
  elseif p.group_execute == true and p.setuid == false then
    r = r .. bit("x", red, p.group_execute)
  elseif p.group_execute == false and p.setuid == true then
    r = r .. bit("S", red, p.group_execute)
  else
    r = r .. bit("s", red, p.group_execute)
  end

  r = r .. bit("r", green, p.other_read)
  r = r .. bit("w", yellow, p.other_write)

  if p.other_execute == false and p.setuid == false then
    r = r .. bit("-", red, p.other_execute)
  elseif p.other_execute == true and p.setuid == false then
    r = r .. bit("x", red, p.other_execute)
  elseif p.other_execute == false and p.setuid == true then
    r = r .. bit("T", red, p.other_execute)
  else
    r = r .. bit("t", red, p.other_execute)
  end

  return r
end

local function stat(node)
  local type = node.mime_essence
  if node.is_symlink then
    if node.is_broken then
      type = "broken symlink"
    else
      type = "symlink to: " .. node.symlink.absolute_path
    end
  end

  return {
    "Type     : " .. type,
    "Size     : " .. node.human_size,
    "Owner    : " .. string.format("%s:%s", node.uid, node.gid),
    "Perm     : " .. permissions(node.permissions),
    "Created  : " .. datetime(node.created),
    "Modified : " .. datetime(node.last_modified)
  }
end

local state = {
  file = "",
  preview = {},
  start_from = 0,
}

local function read(path, size)
  local cmd = "TMUX_POPUP=1 FZF_PREVIEW_COLUMNS=" .. size.width-1 .." FZF_PREVIEW_LINES=" .. size.height-1 .. " fzf-preview " .. xplr.util.shell_escape(path)
  local preview
  local p = io.popen(cmd, "r")
  if p then
    preview = p:read("*a")
    p:close()
  end
  local lines = {}
  for l in preview:gmatch("([^\n]*)\n") do
    table.insert(lines, l)
  end
  return lines
end

local function offset(listing, height)
  local h = height - 3
  local start = (listing.focus - (listing.focus % h))
  local result = {}
  for i = start + 1, start + h, 1 do
    table.insert(result, listing.files[i])
  end
  return result, start
end

local function list(parent, focused, explorer_config)
  local files, focus = {}, 0
  -- local config = { sorters = explorer_config.sorters }
  local ok, nodes = pcall(xplr.util.explore, parent, explorer_config)
  if not ok then
    nodes = {}
  end

  for i, node in ipairs(nodes) do
    local rel = node.relative_path
    if rel == focused then
      focus = i
    end
    if node.is_dir then
      rel = rel .. "/"
    end
    local style = xplr.util.lscolor(node.absolute_path)
    rel = xplr.util.paint(rel, style)
    table.insert(files, rel)
  end

  return { files = files, focus = focus }
end

local function tree_view(listing, height)
  local count = #listing.files
  local files = xplr.util.clone(listing.files)
  local start = 0
  if height then
    files, start = offset(listing, height)
  end
  local res = {"╭─ "}
  for i, file in ipairs(files) do
    local arrow, tree = " ", "├"
    if start + i == listing.focus then
      arrow = "⏵"
    end
    if start + i == count then
      tree = "╰"
    end
    table.insert(res, tree .. arrow .. file)
  end
  return res
end

local function render_left_pane(ctx)
  if ctx.app.pwd == "/" then
    return {}
  end

  local parent = xplr.util.dirname(ctx.app.pwd)
  local focused = xplr.util.basename(ctx.app.pwd)
  local listing = list(parent, focused, ctx.app.explorer_config)
  return tree_view(listing, ctx.layout_size.height)
end

local function render_right_pane(ctx)
  local n = ctx.app.focused_node

  if n then
    if state.file ~= n.absolute_path then
      state.start_from = 0
      state.file = n.absolute_path
      state.preview = {}
    end
    if #state.preview == 0 then
      if n.is_file or (n.is_symlink and n.symlink.is_file) then
        local success, res = pcall(read, n.absolute_path, ctx.layout_size)
        if success and res ~= nil then
          state.preview = res
        else
          state.preview = stat(n)
        end
      elseif n.is_dir or (n.is_symlink and n.symlink.is_dir) then
        local listing = list(n.absolute_path, nil, ctx.app.explorer_config)
        state.preview = tree_view(listing)
      else
        state.preview = stat(n)
      end
    end
  end
  if state.start_from == 0 then
    return table.concat(state.preview, "\n")
  elseif state.start_from > #state.preview - ctx.layout_size.height + 3 then
    state.start_from = #state.preview - ctx.layout_size.height + 3
  end
  local lines = {}
  for i = state.start_from, ctx.layout_size.height + state.start_from - 3 do
    table.insert(lines, state.preview[i])
  end
  return table.concat(lines, "\n")
end

local left_pane = {
  CustomContent = {
    body = {
      DynamicList = {
        render = "custom.tri_pane.render_left_pane",
      },
    },
  },
}

local right_pane = {
  CustomContent = {
    body = {
      DynamicParagraph = {
        render = "custom.tri_pane.render_right_pane",
      },
    },
  },
}

local function setup(args)
  args = args or {}

  if args.as_default_layout == nil then
    args.as_default_layout = true
  end

  args.layout_key = args.layout_key or "T"

  args.left_pane_width = args.left_pane_width or { Percentage = 20 }
  args.middle_pane_width = args.middle_pane_width or { Percentage = 50 }
  args.right_pane_width = args.right_pane_width or { Percentage = 30 }

  args.left_pane_renderer = args.left_pane_renderer or render_left_pane
  args.right_pane_renderer = args.right_pane_renderer or render_right_pane

  xplr.fn.custom.tri_pane = {}
  xplr.fn.custom.tri_pane.toggle = function(ctx)
    local on = xplr.util.to_json(ctx.layout):find("tri_pane") ~= nil
    return {
      "PopMode",
      on and { SwitchLayoutBuiltin = "default" } or { SwitchLayoutCustom = "tri_pane" },
    }
  end
  xplr.fn.custom.tri_pane.render_left_pane = args.left_pane_renderer
  xplr.fn.custom.tri_pane.render_right_pane = args.right_pane_renderer
  xplr.fn.custom.tri_pane.scroll_up = function()
    state.start_from = state.start_from - 5
    if state.start_from < 0 then
      state.start_from = 0
    end
  end
  xplr.fn.custom.tri_pane.scroll_down = function()
    state.start_from = state.start_from + 5
  end
  xplr.fn.custom.tri_pane.scroll_to_end = function()
    if state.start_from == 0 then
      state.start_from = 9999999
    else
      state.start_from = 0
    end
  end

  local layout = {
    Horizontal = {
      config = {
        constraints = {
          args.left_pane_width,
          args.middle_pane_width,
          args.right_pane_width,
        },
      },
      splits = {
        left_pane,
        "Table",
        right_pane,
      },
    },
  }

  local full_layout = {
    Vertical = {
      config = {
        constraints = {
          { Length = 3 },
          { Min = 1 },
          { Length = 3 },
        },
      },
      splits = {
        "SortAndFilter",
        layout,
        "InputAndLogs",
      },
    },
  }

  xplr.config.layouts.custom.tri_pane = full_layout

  if args.as_default_layout then
    xplr.config.layouts.builtin.default = full_layout
  else
    xplr.config.layouts.custom.tri_pane = full_layout
    xplr.config.modes.builtin.switch_layout.key_bindings.on_key[args.layout_key] = {
      help = "tri pane",
      messages = {
        "PopMode",
        { SwitchLayoutCustom = "tri_pane" },
      },
    }
  end
  xplr.config.modes.builtin.default.key_bindings.on_key["ctrl-u"] = {
    help = "scroll up preview",
    messages = { { CallLuaSilently = "custom.tri_pane.scroll_up" } },
  }
  xplr.config.modes.builtin.default.key_bindings.on_key["ctrl-d"] = {
    help = "scroll down preview",
    messages = { { CallLuaSilently = "custom.tri_pane.scroll_down" } },
  }
  xplr.config.modes.builtin.default.key_bindings.on_key["ctrl-g"] = {
    help = "scroll preview to top / bottom",
    messages = { { CallLuaSilently = "custom.tri_pane.scroll_to_end" } },
  }
end

return { setup = setup }
