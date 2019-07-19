
local ffi = require 'ffi'

local sim = {
  ['fn'] = {},
  ['combinational'] = {},
  ['time'] = 0,
  ['clock_names'] = {},
  ['clock_scales'] = {},
  ['signals'] = {},
  ['trace'] = false,
  ['s'] = {}
}

local signals = {}

local vcd_file
local vcd_ids = {}

local reg_file
local reg_names = {}

local cycles = 0

sim.create_clock = function(clk, scale)
  sim.fn[clk] = {}
  sim.clock_scales[clk] = scale
  table.insert(sim.clock_names, clk)
end

sim.always = function(clk, fn)
  table.insert(sim.fn[clk], fn)
end

sim.comb = function(list, fn)
  local sensitivity = {}
  for _, signal in pairs(list) do
    sensitivity[signal] = true
  end
  table.insert(sim.combinational, { sensitivity, fn })
end

sim.create_signal = function(fullname, size)
  local mod, name = string.match(fullname, '(.-)_(.+)')
  reg_names[mod] = reg_names[mod] or {}
  reg_names[mod][name] = fullname
  sim.signals[mod] = sim.signals[mod] or {}
  table.insert(sim.signals[mod], { name, size })
end

sim.start = function(max_cycles)
  
  cycles = max_cycles or -1
  
  -- create signals
  cdef = 'typedef struct {'
  for mod, signals in pairs(sim.signals) do
    for _, signal in pairs(signals) do
      if signal[2] == 1 then
        cdef = cdef .. string.format('uint8_t %s_%s:1;', mod, signal[1])
      else
        cdef = cdef .. string.format('uint%d_t %s_%s;', signal[2], mod, signal[1])
      end
    end
    
    -- if a signal changes then trigger the corresponding comb
    if _G[mod] == nil then _G[mod] = {} end
    setmetatable(_G[mod], {
      __index = function(obj, property)
        return reg_file[reg_names[mod][property]]
      end;
      __newindex = function(obj, property, newValue)
        if reg_file[reg_names[mod][property]] ~= newValue then
          reg_file[reg_names[mod][property]] = newValue
          for i=1, #sim.combinational do
            if sim.combinational[i][1][reg_names[mod][property]] then
              sim.combinational[i][2]()
            end
          end
        end
      end;
    })
    
  end
  
  cdef = cdef .. '} signals;'
  ffi.cdef(cdef)
  reg_file = ffi.new('signals')
  
end

sim.update = function()
  
  if cycles > 0 and sim.time >= cycles then return end
  
  -- execute sequential logic
  for i=1, #sim.clock_names do
    
    local clock_name = sim.clock_names[i]
    
    if sim.time % sim.clock_scales[clock_name] == 0 then
      for i=1, #sim.fn[clock_name] do
        sim.fn[clock_name][i]()
      end
    end

  end
  
  if sim.trace then

    -- create VCD header
    if sim.time == 0 then
      ids = {}
      -- love2d:
      -- vcd_file, err = love.filesystem.newFile('dump.vcd')
      -- vcd_file:open('w')
      vcd_file = io.open('dump.vcd', 'w')
      vcd_file:write('$timescale 1ps $end\r\n')
      local id = 40
      
      -- variables declaration
      for mod, signals in pairs(sim.signals) do
        vcd_file:write('$scope module ' .. mod .. ' $end\r\n') 

        for _, signal in pairs(signals) do
          local sname = signal[1]
          local ssize = signal[2]
          vcd_file:write(string.format('$var %s %d %c %s $end\r\n', 'wire', ssize, id, sname))
          vcd_ids[mod .. sname] = id
          id = id + 1
        end

        vcd_file:write('$upscope $end\r\n')
      end
      
      -- add clocks
      vcd_file:write('$scope module TOP $end\r\n') 
      for i=1, #sim.clock_names do
        local sname = sim.clock_names[i]
        vcd_file:write(string.format('$var reg %d %c %s $end\r\n', 1, id, sname))
        vcd_ids['clocks' .. sname] = id
        id = id + 1
      end
      vcd_file:write('$upscope $end\r\n')
      
      vcd_file:write('$enddefinitions $end\r\n')
      
    end
    
    -- write time
    vcd_file:write(string.format('#%d\r\n', sim.time))
    
    -- dump clocks
    for i=1, #sim.clock_names do
      local sname = sim.clock_names[i]
      local v = sim.time % sim.clock_scales[sname] < sim.clock_scales[sname] / 2 and 1 or 0
      vcd_file:write(string.format('%s%c\r\n', v, vcd_ids['clocks' .. sname]))
    end

    -- dump signals
    for mod, signals in pairs(sim.signals) do
      for _, signal in pairs(signals) do
        local sname = signal[1]
        
        local bits = signal[2]
        if bits > 1 then
          
          local n = reg_file[reg_names[mod][sname]]
          local t = {} -- will contain the bits        
          for b = bits, 1, -1 do
            t[b] = math.fmod(n, 2)
            n = math.floor((n - t[b]) / 2)
          end
   
          vcd_file:write(string.format('b%s %c\r\n', table.concat(t), vcd_ids[mod .. sname]))
          
        else
          vcd_file:write(string.format('%s%c\r\n', reg_file[reg_names[mod][sname]], vcd_ids[mod .. sname]))
        end
        
      end
    end

  end
  
  sim.time = sim.time + 1
end

return sim