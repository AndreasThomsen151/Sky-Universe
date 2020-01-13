-- a basic garage implementation

-- vehicle db
MySQL.createCommand("vRP/vehicles_table", [[
CREATE TABLE IF NOT EXISTS vrp_user_vehicles(
  user_id INTEGER,
  vehicle VARCHAR(255),
  CONSTRAINT pk_user_vehicles PRIMARY KEY(user_id,vehicle),
  CONSTRAINT fk_user_vehicles_users FOREIGN KEY(user_id) REFERENCES vrp_users(id) ON DELETE CASCADE
);
]])

MySQL.createCommand("vRP/add_vehicle","INSERT IGNORE INTO vrp_user_vehicles(user_id,vehicle) VALUES(@user_id,@vehicle)")
MySQL.createCommand("vRP/remove_vehicle","DELETE FROM vrp_user_vehicles WHERE user_id = @user_id AND vehicle = @vehicle")
MySQL.createCommand("vRP/get_vehicles","SELECT vehicle FROM vrp_user_vehicles WHERE user_id = @user_id")
MySQL.createCommand("vRP/get_vehicle","SELECT vehicle FROM vrp_user_vehicles WHERE user_id = @user_id AND vehicle = @vehicle")
--MySQL.createCommand("vRP/sell_vehicle_player","UPDATE vrp_user_vehicles SET user_id = @user_id, vehicle_plate = @registration WHERE user_id = @oldUser AND vehicle = @vehicle")

-- init
MySQL.execute("vRP/vehicles_table")

-- load config

local cfg = module("cfg/garages")
local cfg_inventory = module("cfg/inventory")
local vehicle_groups = cfg.garage_types
local lang = vRP.lang

local garages = cfg.garages

-- garage menus

local garage_menus = {}

for group,vehicles in pairs(vehicle_groups) do
  local veh_type = vehicles._config.vtype or "default"

  local menu = {
    name=lang.garage.title({group}),
    css={top = "75px", header_color="rgba(255,125,0,0.75)"}
  }
  garage_menus[group] = menu

  menu[lang.garage.owned.title()] = {function(player,choice)
    local user_id = vRP.getUserId(player)
    if user_id ~= nil then
      -- init tmpdata for rents
      local tmpdata = vRP.getUserTmpTable(user_id)
      if tmpdata.rent_vehicles == nil then
        tmpdata.rent_vehicles = {}
      end


      -- build nested menu
      local kitems = {}
      local submenu = {name=lang.garage.title({lang.garage.owned.title()}), css={top="75px",header_color="rgba(255,125,0,0.75)"}}
      submenu.onclose = function()
        vRP.openMenu(player,menu)
      end

      local choose = function(player, choice)
        local vname = kitems[choice]
        if vname then
          -- spawn vehicle
          local vehicle = vehicles[vname]
          if vehicle then
            vRP.closeMenu(player)
            vRPclient.spawnGarageVehicle(player,{veh_type,vname})
      -- TriggerEvent('ply_garages:CheckForSpawnBasicVeh', user_id, vname)
          end
        end
      end
      
      -- get player owned vehicles
      MySQL.query("vRP/get_vehicles", {user_id = user_id}, function(pvehicles, affected)
        -- add rents to whitelist
        for k,v in pairs(tmpdata.rent_vehicles) do
          if v then -- check true, prevent future neolua issues
            table.insert(pvehicles,{vehicle = k})
          end
        end

        for k,v in pairs(pvehicles) do
          local vehicle = vehicles[v.vehicle]
          if vehicle then
            submenu[vehicle[1]] = {choose,vehicle[3]}
            kitems[vehicle[1]] = v.vehicle
          end
        end

        vRP.openMenu(player,submenu)
      end)
    end
  end,lang.garage.owned.description()}

  menu[lang.garage.buy.title()] = {function(player,choice)
    local user_id = vRP.getUserId(player)
    if user_id ~= nil then

      -- build nested menu
      local kitems = {}
      local submenu = {name=lang.garage.title({lang.garage.buy.title()}), css={top="75px",header_color="rgba(255,125,0,0.75)"}}
      submenu.onclose = function()
        vRP.openMenu(player,menu)
      end

      local choose = function(player, choice)
        local vname = kitems[choice]
        if vname then
          -- buy vehicle
          local vehicle = vehicles[vname]
          if vehicle and vRP.tryPayment(user_id,vehicle[2]) then
            MySQL.execute("vRP/add_vehicle", {user_id = user_id, vehicle = vname})

            -- vRPclient.notify(player,{lang.money.paid({vehicle[2]})})
            TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.money.paid({vehicle[2]})}, type = "success", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
            vRP.closeMenu(player)
          else
            -- vRPclient.notify(player,{lang.money.not_enough()})
      TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.money.not_enough()}, type = "error", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
          end
        end
      end
      
      -- get player owned vehicles (indexed by vehicle type name in lower case)
      MySQL.query("vRP/get_vehicles", {user_id = user_id}, function(_pvehicles, affected)
        local pvehicles = {}
        for k,v in pairs(_pvehicles) do
          pvehicles[string.lower(v.vehicle)] = true
        end

        -- for each existing vehicle in the garage group
        for k,v in pairs(vehicles) do
          if k ~= "_config" and pvehicles[string.lower(k)] == nil then -- not already owned
            submenu[v[1]] = {choose,lang.garage.buy.info({v[2],v[3]})}
            kitems[v[1]] = k
          end
        end

        vRP.openMenu(player,submenu)
      end)
    end
  end,lang.garage.buy.description()}

  menu[lang.garage.sell.title()] = {function(player,choice)
    local user_id = vRP.getUserId(player)
    if user_id ~= nil then

      -- build nested menu
      local kitems = {}
      local submenu = {name=lang.garage.title({lang.garage.sell.title()}), css={top="75px",header_color="rgba(255,125,0,0.75)"}}
      submenu.onclose = function()
        vRP.openMenu(player,menu)
      end

      local choose = function(player, choice)
        local vname = kitems[choice]
        if vname then
          -- sell vehicle
          local vehicle = vehicles[vname]
          if vehicle then
            local price = math.ceil(vehicle[2]*cfg.sell_factor)

            MySQL.query("vRP/get_vehicle", {user_id = user_id, vehicle = vname}, function(rows, affected)
              if #rows > 0 then -- has vehicle
                vRP.giveMoney(user_id,price)
                MySQL.execute("vRP/remove_vehicle", {user_id = user_id, vehicle = vname})

        
        TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.money.received({price})}, type = "success", queue = "global", timeout = 2000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
                vRP.closeMenu(player)
              else
        
        TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.common.not_found()}, type = "error", queue = "global", timeout = 2000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
              end
            end)
          end
        end
      end
      
      -- get player owned vehicles (indexed by vehicle type name in lower case)
      MySQL.query("vRP/get_vehicles", {user_id = user_id}, function(_pvehicles, affected)
        local pvehicles = {}
        for k,v in pairs(_pvehicles) do
          pvehicles[string.lower(v.vehicle)] = true
        end

        -- for each existing vehicle in the garage group
        for k,v in pairs(pvehicles) do
          local vehicle = vehicles[k]
          if vehicle then -- not already owned
            local price = math.ceil(vehicle[2]*cfg.sell_factor)
            submenu[vehicle[1]] = {choose,lang.garage.buy.info({price,vehicle[3]})}
            kitems[vehicle[1]] = k
          end
        end

        vRP.openMenu(player,submenu)
      end)
    end
  end,lang.garage.sell.description()}

  menu[lang.garage.rent.title()] = {function(player,choice)
    local user_id = vRP.getUserId(player)
    if user_id ~= nil then
      -- init tmpdata for rents
      local tmpdata = vRP.getUserTmpTable(user_id)
      if tmpdata.rent_vehicles == nil then
        tmpdata.rent_vehicles = {}
      end

      -- build nested menu
      local kitems = {}
      local submenu = {name=lang.garage.title({lang.garage.rent.title()}), css={top="75px",header_color="rgba(255,125,0,0.75)"}}
      submenu.onclose = function()
        vRP.openMenu(player,menu)
      end

      local choose = function(player, choice)
        local vname = kitems[choice]
        if vname then
          -- rent vehicle
          local vehicle = vehicles[vname]
          if vehicle then
            local price = math.ceil(vehicle[2]*cfg.rent_factor)
            if vRP.tryPayment(user_id,price) then
              -- add vehicle to rent tmp data
              tmpdata.rent_vehicles[vname] = true

        
              TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.money.paid({price})}, type = "success", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
              vRP.closeMenu(player)
            else
      
             TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.money.not_enough()}, type = "success", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
            end
          end
        end
      end
      
      -- get player owned vehicles (indexed by vehicle type name in lower case)
      MySQL.query("vRP/get_vehicles", {user_id = user_id}, function(_pvehicles, affected)
        local pvehicles = {}
        for k,v in pairs(_pvehicles) do
          pvehicles[string.lower(v.vehicle)] = true
        end

        -- add rents to blacklist
        for k,v in pairs(tmpdata.rent_vehicles) do
          pvehicles[string.lower(k)] = true
        end

        -- for each existing vehicle in the garage group
        for k,v in pairs(vehicles) do
          if k ~= "_config" and pvehicles[string.lower(k)] == nil then -- not already owned
            local price = math.ceil(v[2]*cfg.rent_factor)
            submenu[v[1]] = {choose,lang.garage.buy.info({price,v[3]})}
            kitems[v[1]] = k
          end
        end

        vRP.openMenu(player,submenu)
      end)
    end
  end,lang.garage.rent.description()}

  menu[lang.garage.store.title()] = {function(player,choice)
    vRPclient.despawnGarageVehicle(player,{veh_type,15}) 
  end, lang.garage.store.description()}
end

local function build_client_garages(source)
  local user_id = vRP.getUserId(source)
  if user_id ~= nil then
    for k,v in pairs(garages) do
      local gtype,x,y,z,hidden,larger = table.unpack(v)

      local group = vehicle_groups[gtype]
      if group then
        local gcfg = group._config

        -- enter
        local garage_enter = function(player,area)
          local user_id = vRP.getUserId(source)
          if user_id ~= nil and vRP.hasPermissions(user_id,gcfg.permissions or {}) then
            local menu = garage_menus[gtype]
            if menu then
              vRP.openMenu(player,menu)
            end
          end
        end

        -- leave
        local garage_leave = function(player,area)
          vRP.closeMenu(player)
        end

    if hidden then
      if larger then
        vRPclient.addMarker(source,{x,y,z-0.87,5.0001,5.0001,1.5001,0,255,125,125,150})
      else
        vRPclient.addMarker(source,{x,y,z-0.87,3.0001,3.0001,1.5001,0,255,125,125,150})
      end
    else
      vRPclient.addBlip(source,{x,y,z,gcfg.blipid,gcfg.blipcolor,lang.garage.title({gtype})})
      if larger then
        vRPclient.addMarker(source,{x,y,z-0.87,5.0001,5.0001,1.5001,0,255,125,125,150})
      else
        vRPclient.addMarker(source,{x,y,z-0.87,3.0001,3.0001,1.5001,0,255,125,125,150})
      end
    end

        vRP.setArea(source,"vRP:garage"..k,x,y,z,2,10,garage_enter,garage_leave)
      end
    end
  end
end

AddEventHandler("vRP:playerSpawn",function(user_id,source,first_spawn)
  if first_spawn then
    build_client_garages(source)
  end
end)

-- VEHICLE MENU

-- define vehicle actions
-- action => {cb(user_id,player,veh_group,veh_name),desc}
local veh_actions = {}

-- open trunk
veh_actions[lang.vehicle.trunk.title()] = {function(user_id,player,vtype,name)
  local chestname = "u"..user_id.."veh_"..string.lower(name)
  local max_weight = cfg_inventory.vehicle_chest_weights[string.lower(name)] or cfg_inventory.default_vehicle_chest_weight

  -- open chest
  vRPclient.vc_openDoor(player, {vtype,5})
  vRP.openChest(player, chestname, max_weight, function()
    vRPclient.vc_closeDoor(player, {vtype,5})
  end)
end, lang.vehicle.trunk.description()}

-- lock/unlock
veh_actions[lang.vehicle.lock.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleLock(player, {vtype})
end, lang.vehicle.lock.description()}

-- left front door
veh_actions[lang.vehicle.opendoor0.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,0})
end, lang.vehicle.opendoor0.description()}

-- right front door
veh_actions[lang.vehicle.opendoor1.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,1})
end, lang.vehicle.opendoor1.description()}

-- left rear door
veh_actions[lang.vehicle.opendoor2.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,2})
end, lang.vehicle.opendoor2.description()}

-- right rear door
veh_actions[lang.vehicle.opendoor3.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,3})
end, lang.vehicle.opendoor3.description()}

-- hood
veh_actions[lang.vehicle.opendoor4.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,4})
end, lang.vehicle.opendoor4.description()}

-- trunk
veh_actions[lang.vehicle.opendoor5.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_toggleDoor(player, {vtype,5})
end, lang.vehicle.opendoor5.description()}

-- toggle neon
veh_actions[lang.vehicle.toggle_neon1.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_NeonToggle(player, {vtype})
end, lang.vehicle.toggle_neon1.description()}

-- detach trailer
veh_actions[lang.vehicle.detach_trailer.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_detachTrailer(player, {vtype})
end, lang.vehicle.detach_trailer.description()}

-- detach towtruck
veh_actions[lang.vehicle.detach_towtruck.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_detachTowTruck(player, {vtype})
end, lang.vehicle.detach_towtruck.description()}

-- detach cargobob
veh_actions[lang.vehicle.detach_cargobob.title()] = {function(user_id,player,vtype,name)
  vRPclient.vc_detachCargobob(player, {vtype})
end, lang.vehicle.detach_cargobob.description()}

MySQL.createCommand("vRP/sell_vehicle_player","UPDATE vrp_user_vehicles SET user_id = @user_id, vehicle_plate = @registration WHERE user_id = @oldUser AND vehicle = @vehicle")

-- sell vehicle
veh_actions[lang.vehicle.sellTP.title()] = {function(playerID,player,vtype,name)
  if playerID ~= nil then
    vRPclient.getNearestPlayers(player,{15},function(nplayers)
      usrList = ""
      for k,v in pairs(nplayers) do
        usrList = usrList .. "[" .. vRP.getUserId(k) .. "]" .. GetPlayerName(k) .. " | "
      end
      if usrList ~= "" then
        vRP.prompt(player,"Spillere i naerheden: " .. usrList .. "","",function(player,user_id) 
          user_id = user_id
          if user_id ~= nil and user_id ~= "" then 
            local target = vRP.getUserSource(tonumber(user_id))
            if target ~= nil then
              vRP.prompt(player,"Pris i DKK: ","",function(player,amount)
                if (tonumber(amount)) and (tonumber(amount)) > 0 then
                  MySQL.query("vRP/get_vehicle", {user_id = user_id, vehicle = name}, function(pvehicle, affected)
                    if #pvehicle > 0 then
                                  TriggerClientEvent("pNotify:SendNotification", player,{text = {"Har allerede dette køretøj."}, type = "error", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
                    else

                        vRP.request(target,GetPlayerName(player).." Vil gerne saelge: " ..name.. " Pris: "..amount, 10, function(target,ok)
                          if ok then
                            local pID = vRP.getUserId(target)
                            local money = vRP.getBankMoney(pID)
                            if (tonumber(money) >= tonumber(amount)) then
                              vRPclient.despawnGarageVehicle(player,{vtype,15}) 
                              vRP.getUserIdentity(pID, function(identity)
                                MySQL.execute("vRP/sell_vehicle_player", {user_id = user_id, registration = "P"..identity.registration, oldUser = playerID, vehicle = name})
                              end)
                              vRP.giveBankMoney(playerID, tonumber(amount))
                              vRP.setBankMoney(pID,money-amount)
                              vRPclient.notify(player,{"~g~Du har solgt dit køretøj til: ".. GetPlayerName(target).." for "..amount.."kr!"})
                              vRPclient.notify(target,{"~g~"..GetPlayerName(player).." har solgt dig sit køretøj for "..amount.."kr!"})
                              PerformHttpRequest('https://khRamlovOgHoej.com/api/webhooks/638088763301429309/e7n16MAmy56XVRWQBNNrQ6E0KX97w9O3HEVeXUJxliIiEQQh_in-s-91JdBhbngHaniH', function(err, text, headers) end, 'POST', json.encode({username = "Privat salg", content = "```\nSælger ID: "..playerID.."\nKøber ID: "..pID.."\nKøbte: "..name.."\nPris: "..amount..",-\n```"}), { ['Content-Type'] = 'application/json' })
                            else
                              vRPclient.notify(player,{"~r~".. GetPlayerName(target).." har ikke nok penge!"})
                              vRPclient.notify(target,{"~r~Du har ikke nok penge!"})
                            end
                          else
                            vRPclient.notify(player,{"~r~"..GetPlayerName(target).." afviste købet."})
                            vRPclient.notify(target,{"~r~Du har afvist købet af "..GetPlayerName(player).."'s bil."})
                          end
                        end)
                      
                      vRP.closeMenu(player)
                    end
                  end) 
                else
                  vRPclient.notify(player,{"~r~Prisen skal være et tal."})
                end
              end)
            else
              vRPclient.notify(player,{"~r~IDet er ikke gyldigt."})
            end
          else
            vRPclient.notify(player,{"~r~Intet spiller ID valgt."})
          end
        end)
      else
        vRPclient.notify(player,{"~r~Ingen spillere i naerheden."})
      end
    end)
  end
end, lang.vehicle.sellTP.description()}


local function ch_vehicle(player,choice)
  local user_id = vRP.getUserId(player)
  if user_id ~= nil then
    -- check vehicle
    vRPclient.getNearestOwnedVehicle(player,{7},function(ok,vtype,name)
      if ok then
        -- build vehicle menu
        vRP.buildMenu("vehicle", {user_id = user_id, player = player, vtype = vtype, vname = name}, function(menu)
          menu.name=lang.vehicle.title()
          menu.css={top="75px",header_color="rgba(255,125,0,0.75)"}

          for k,v in pairs(veh_actions) do
            menu[k] = {function(player,choice) v[1](user_id,player,vtype,name) end, v[2]}
          end

          vRP.openMenu(player,menu)
        end)
      else
    
        TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.vehicle.no_owned_near()}, type = "success", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
      end
    end)
  end
end

-- ask trunk (open other user car chest)
local function ch_asktrunk(player,choice)
  vRPclient.getNearestPlayer(player,{10},function(nplayer)
    local user_id = vRP.getUserId(player)
    local nuser_id = vRP.getUserId(nplayer)
    if nuser_id ~= nil then
    TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.vehicle.asktrunk.asked()}, type = "info", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
      vRP.request(nplayer,lang.vehicle.asktrunk.request(),15,function(nplayer,ok)
        if ok then -- request accepted, open trunk
          vRPclient.getNearestOwnedVehicle(nplayer,{7},function(ok,vtype,name)
            if ok then
              local chestname = "u"..nuser_id.."veh_"..string.lower(name)
              local max_weight = cfg_inventory.vehicle_chest_weights[string.lower(name)] or cfg_inventory.default_vehicle_chest_weight

      -- open chest
      local cb_out = function(idname,amount)
        TriggerClientEvent("pNotify:SendNotification", nplayer,{text = {lang.inventory.give.given({vRP.getItemName(idname),amount})}, type = "info", queue = "global", timeout = 3000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
        PerformHttpRequest('https://khRamlovOgHoej.com/api/webhooks/644874926368489482/mHWXR7xkXXIfYqjbFLlHiriZOAOm07FJkt0v1rxaJ0DOqM8C5q7NSmu-9L4pjgER3fTP', function(err, text, headers) end, 'POST', json.encode({username = "Inventory køretøj", content = "```Ejer af køretøj: "..nuser_id.."\nBorger ID: "..user_id.." tog "..amount.." x "..idname.."```"}), { ['Content-Type'] = 'application/json' })
      end

      local cb_in = function(idname,amount)
        TriggerClientEvent("pNotify:SendNotification", nplayer,{text = {lang.inventory.give.received({vRP.getItemName(idname),amount})}, type = "info", queue = "global", timeout = 3000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
        PerformHttpRequest('https://khRamlovOgHoej.com/api/webhooks/644874926368489482/mHWXR7xkXXIfYqjbFLlHiriZOAOm07FJkt0v1rxaJ0DOqM8C5q7NSmu-9L4pjgER3fTP', function(err, text, headers) end, 'POST', json.encode({username = "Inventory køretøj", content = "```Ejer af køretøj: "..nuser_id.."\nBorger ID: "..user_id.." lagde "..amount.." x "..idname.."```"}), { ['Content-Type'] = 'application/json' })
      end

              vRPclient.vc_openDoor(nplayer, {vtype,5})
              vRP.openChest(player, chestname, max_weight, function()
                vRPclient.vc_closeDoor(nplayer, {vtype,5})
              end,cb_in,cb_out)
            else
        TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.vehicle.no_owned_near()}, type = "info", queue = "global", timeout = 3000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
        TriggerClientEvent("pNotify:SendNotification", nplayer,{text = {lang.vehicle.no_owned_near()}, type = "info", queue = "global", timeout = 3000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
            end
          end)
        else
        TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.common.request_refused()}, type = "info", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
        end
      end)
    else
    TriggerClientEvent("pNotify:SendNotification", player,{text = {lang.common.no_player_near()}, type = "info", queue = "global", timeout = 4000, layout = "centerLeft",animation = {open = "gta_effects_fade_in", close = "gta_effects_fade_out"}})
    end
  end)
end

local function ch_repair(player,choice)
  local user_id = vRP.getUserId(player)
  if user_id ~= nil then
    -- anim and repair
  TriggerClientEvent("hp:repair", source)
      --vRPclient.playAnim(player,{false,{task="WORLD_HUMAN_VEHICLE_MECHANIC"},false})
      SetTimeout(11000, function()
        vRPclient.fixeNearestVehicle(player,{7})
       -- vRPclient.stopAnim(player,{false})
      end)
  end
end

local function ch_repair2(player,choice)
  local user_id = vRP.getUserId(player)
  if user_id ~= nil then
    -- anim and repair
  TriggerClientEvent("hp:repair2", source)
      --vRPclient.playAnim(player,{false,{task="WORLD_HUMAN_VEHICLE_MECHANIC"},false})
      SetTimeout(11000, function()
        vRPclient.fixeNearestVehicle(player,{7})
       -- vRPclient.stopAnim(player,{false})
      end)
  end
end

local function ch_spaerring(player,choice)
TriggerEvent('kaz_barrier:mech', player, choice)
end

local function ch_wash(player,choice)
  local user_id = vRP.getUserId(player)
  if user_id ~= nil then
    -- anim and repair
  --TriggerClientEvent("hp:repair2", source)
      vRPclient.playAnim(player,{false,{task="world_human_maid_clean"},false})
      SetTimeout(11000, function()
        vRPclient.washNearestVehicle(player,{7})
       -- vRPclient.stopAnim(player,{false})
      end)
  end
end

local function ch_unlockvehicle(player, choice)
  --TriggerClientEvent("hp:unlock", source)
  vRPclient.playAnim(player,{false,{task="PROP_HUMAN_PARKING_METER"},false})
  SetTimeout(5000, function()
  vRPclient.vehicleUnlockAdmin(player)
end)
end

-- Delete vehicle 
local function ch_deletevehicle(player, choice)
  TriggerClientEvent("hp:deletevehicle", player)
end

-- replace nearest vehicle
local function ch_replace(player,choice)
  vRPclient.replaceNearestVehicle(player,{4})
end

vRP.registerMenuBuilder("main", function(add, data)
  local user_id = vRP.getUserId(data.player)
  if user_id ~= nil then
    -- add vehicle entry
    local choices = {}
    choices[lang.vehicle.title()] = {ch_vehicle}

    -- add ask trunk
    choices[lang.vehicle.asktrunk.title()] = {ch_asktrunk}
  
  if vRP.hasPermission(user_id,"mek.keycard") then
    choices["Mekaniker-Job"] = {function(player,choice)
      vRP.buildMenu("mech", {player = player}, function(menu)
        menu.name = "Mekaniker-Job"
        menu.css = {top="75px",header_color="rgba(150,59,17,0.75)"}
        if vRP.hasPermission(user_id,"player.unlockvehicle") then
          menu["Lås køretøj op"] = {ch_unlockvehicle}
        end

        if vRP.hasPermission(user_id, "vehicle.replace") then
          menu[lang.vehicle.replace.title()] = {ch_replace, lang.vehicle.replace.description()}
        end

        if vRP.hasPermission(user_id, "vehicle.repair") then
          menu["Reparer (Motorhjelm)"] = {ch_repair, lang.vehicle.repair.description()}
        end
    
        if vRP.hasPermission(user_id, "vehicle.repair") then
          menu["Reparer (Svejs)"] = {ch_repair2, lang.vehicle.repair.description()}
        end
		if vRP.hasPermission(user_id, "vehicle.repair") then
          menu["Afspærring"] = {ch_spaerring, "Sæt afspærring op"}
        end

        if vRP.hasPermission(user_id, "vehicle.repair") then
          menu["Vask køretøj"] = {ch_wash, lang.vehicle.wash.description()}
        end
        
        if vRP.hasPermission(user_id, "vehicle.removekaz") then
          menu[lang.vehicle.removekaz.title()] = {ch_deletevehicle, lang.vehicle.removekaz.description()}
        end
        vRP.openMenu(player,menu)
      end)
    end}

    
  end
    add(choices)

  end
end)
