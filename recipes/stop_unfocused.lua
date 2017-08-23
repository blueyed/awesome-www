--- Manage sending SIGSTOP signals to special clients when they are unfocused.
--
-- Clients with ontop = true are ignored.
--
-- You can add a client to sigstop_unfocus.ignore_clients to ignore it:
--
--     stop_unfocused.ignore_clients[c] = true
--
-- To not ignore it anymore, unset it:
--
--     stop_unfocused.ignore_clients[c] = nil

local awful = require('awful')
local timer = require('gears.timer')

local stop_unfocused = {}

-- TODO: do not stop "Sending Message" client window with Thunderbird.
--       class: Thunderbird, name: Sending Message, instance: Dialog
stop_unfocused.config = {
  rules = {
    {rule = {class = 'qutebrowser'}},
    {rule = {class = 'Firefox'}},
    {rule = {class = 'Thunderbird'}},
  },
  stop_timeout = 10,
}

stop_unfocused.ignore_clients = {}

-- Active timers.
local sigstop_timers = {}

local sigstopped_clients = {}
function stop_unfocused.sigstop(c)
  if c.pid then
    awesome.kill(c.pid, 19)
    awful.spawn('pkill -STOP -g ' .. c.pid)
    sigstopped_clients[c] = true
  end
end

function stop_unfocused.sigcont(c)
  if c.pid then
    awesome.kill(c.pid, 18)
    awful.spawn('pkill -CONT -g ' .. c.pid)
    sigstopped_clients[c] = nil
  end
end

local function delayed_cont(c, mouse_coords)
  if client.focus == c then
    local coords = mouse.coords()
    if mouse_coords.x == coords.x and mouse_coords.y == coords.y then
      stop_unfocused.sigcont(c)
    else
      timer.start_new(0.05, function()
        timer.delayed_call(function() delayed_cont(c, coords) end)
      end)
    end
  end
end

local onfocus = function(c)
  if sigstop_timers[c] then
      sigstop_timers[c]:stop()
      sigstop_timers[c] = nil
  end

  if c.pid and sigstopped_clients[c] then
    local coords = mouse.coords()
    timer.delayed_call(function() delayed_cont(c, coords) end)
  end
end
local sigstop_unfocus = function(c)
  if c.pid and not sigstopped_clients[c] and not c.ontop and not stop_unfocused.ignore_clients[c] then
    local rules = awful.rules.matching_rules(c, stop_unfocused.config.rules)
    if #rules > 0 then
      local timeout = stop_unfocused.config.stop_timeout
      for _, entry in ipairs(rules) do
        if entry.timeout then
          timeout = entry.timeout
        end
      end
      if timeout then
        if sigstop_timers[c] then
          sigstop_timers[c]:stop()
        end
        sigstop_timers[c] = timer.start_new(timeout, function()
          if c ~= client.focus and c.pid ~= client.focus.pid then
            stop_unfocused.sigstop(c)
          end
          sigstop_timers[c] = nil
          return false
        end)
      end
    end
  end
end
client.connect_signal("focus", onfocus)
client.connect_signal("unfocus", sigstop_unfocus)

client.connect_signal("request::activate", function(c, context, hints)  --luacheck: no unused args
  if sigstopped_clients[c] then
    stop_unfocused.sigcont(c)
  end
end)

-- Restart any stopped clients when exiting/restarting.
awesome.connect_signal("exit", function()
  for c, _ in pairs(sigstopped_clients) do
    stop_unfocused.sigcont(c)
  end
end)

return stop_unfocused

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
