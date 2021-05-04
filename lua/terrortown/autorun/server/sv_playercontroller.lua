-----------------------------------------------------
------------------- Player Control ------------------
-----------------------------------------------------

PlayerController = PlayerController or {}
PlayerController.__index = PlayerController

setmetatable(PlayerController, {
    __call = function(cls, ...)
        local obj = setmetatable({}, cls)
        obj:__init(...)
        return obj
    end,
})


function PlayerController:__init(c_ply, t_ply, view_flag, net_flag)
    self:StartControl(c_ply, t_ply, view_flag, net_flag)
end

-----------------------------------------------------
------------------- Communication -------------------
-----------------------------------------------------

--util.AddNetworkString("PlayerController:StartControl") -- obsolete
--util.AddNetworkString("PlayerController:EndControl") -- obsolete
util.AddNetworkString("PlayerController:NetControl")
util.AddNetworkString("PlayerController:ControlToSV")
util.AddNetworkString("PlayerController:ControlToCL")

util.AddNetworkString("PlayerController:ControllerCommands")
util.AddNetworkString("PlayerController:NetCommands")

util.AddNetworkString("PlayerController:NetControlTest")

net.Receive("PlayerController:NetControlTest", function(len, c_ply)
    print("Start Control: Bot1 controlling you!")
    local view_flag = net.ReadUInt(2)
    local net_flag = net.ReadUInt(1)
    PlayerController(player.GetBots()[1], c_ply, view_flag, net_flag)
end)

-- General PlayerController Managment 
net.Receive("PlayerController:NetControl", function (len, calling_ply)
    local mode = net.ReadUInt(3)

    -- if controller is already active 
    if calling_ply:IsController() then
        local controller = calling_ply.controller

        -- Start Player Controller
        if mode == PC_CL_START then
            local target_ply = net.ReadEntity()

            -- if aready controlling that person, or is that person
            if target_ply == controller.t_ply or target_ply == calling_ply then return end

            local view_flag = net.ReadUInt(2)
            local net_flag  = net.ReadUInt(1)
            controller:EndControl()

            controller:StartControl(calling_ply, target_ply, view_flag, net_flag)

        -- Stop Player Controller
        elseif mode == PC_CL_END then
            controller:EndControl()

        -- Switch t_ply in Player Controller
        elseif mode == PC_CL_SWITCH then
            local target_ply = net.ReadEntity()
            local view_flag  = calling_ply.controller.view_flag
            local net_flag   = calling_ply.controller.net_flag

            print("Switching to player:", target_ply)
            controller:EndControl()

            controller:StartControl(calling_ply, target_ply, view_flag, net_flag)
        else
            print(alling_ply:Nick() .. " is already controlling, but the control mode is not valid.")        
        end

    -- if calling player is not active controller yet 
    -- and has adming rights
    -- TODO: hook, für weitere sonstige Abfrage hinzufügen
    elseif calling_ply:IsAdmin() or calling_ply:IsSuperAdmin() then
        if mode == PC_CL_START then
            local target_ply = net.ReadEntity()
            local view_flag  = net.ReadUInt(2) or PC_CAM_SIMPLEFIRSTPERSON
            local net_flag   = net.ReadUInt(1) or PC_SERVERSIDE

            -- create new PlayerController
            PlayerController(calling_ply, target_ply, view_flag, net_flag)
        else
            print(calling_ply:Nick() .. " has not valid control mode.")
        end
    else
        print(calling_ply:Nick() .. " does not have the right to start a control.")
    end
end)

-------------- Overriding Network Communication --------------

function net.Incoming( len, client )

    local i = net.ReadHeader()
    local strName = util.NetworkIDToString( i ):lower()

    if client.controller and client.controller["t_ply"] and PC_SV_NET[strName] then
        client = client.controller["t_ply"]
    end

    if ( !strName ) then return end

    local func = net.Receivers[ strName ]
    if ( !func ) then return end

    -- len includes the 16 bit int which told us the message name
    len = len - 16

    func( len, client )
end


local OldSend = OldSend or net.Send

function net.Send(ply)
    if ply.controller and ply.controller["c_ply"] then
        --print("Addressat wird geändert")
        -- if  PC_TARGET_MESSAGES[strName] then            
        --     --print(strName)
        -- end
        local new_ply = ply.controller["c_ply"]

        OldSend( {ply, new_ply} )
        return
    end

    OldSend( ply )
end



-- -- TODO: integrate into NetCOntrol
-- net.Receive("PlayerController:StartControl", function (len, calling_ply)
--     if (calling_ply:IsAdmin() or calling_ply:IsSuperAdmin()) then
--         local target_ply = net.ReadEntity()
--         local view_flag = net.ReadUInt(2)

--         --PlayerController:StartControl(calling_ply, target_ply, view_flag)
--     end
-- end)

-- net.Receive("PlayerController:EndControl", function (len, calling_ply)
--     if (calling_ply:IsAdmin() or calling_ply:IsSuperAdmin()) then -- or (calling_ply.controller and (calling_ply.controller["c_ply"]:IsAdmin() or calling_ply.controller["c_ply"]:IsSuperAdmin())) then
--         PlayerController:EndControl()
--     end
-- end)

function PlayerController.NetSend(ply, tbl)
    net.Start("PlayerController:ControlToCL")
        net.WriteTable(tbl)
    OldSend(ply)
end

-----------------------------------------------------
----------------- Control Functions -----------------
-----------------------------------------------------

function PlayerController:StartControl(c_ply, t_ply, view_flag, net_flag)

    if self.isActive then return end
    self.isActive = true

    -- Add Controlling Hooks
    hook.Add("StartCommand", "PlayerController:OverrideCommands", PlayerController.overrideCommands)
    hook.Add("DoAnimationEvent", "PlayerController:PreventAnimations", PlayerController.preventAnimations)
    --hook.Add("SetupMove", "PlayerController:SetupMove", PlayerController.preventAttacking)
    hook.Add("FinishMove", "PlayerController:DisableControllerMovment", PlayerController.disableMovment)

    hook.Add("PlayerDeath", "PlayerController:PlayerDied", PlayerController.playerDied)
    hook.Add("PlayerSwitchWeapon", "PlayerController:DisableWeaponSwitch", PlayerController.disableWeaponSwitch)
    hook.Add("WeaponEquip", "PlayerController:UpdateTargetInventory", function(wep, ply) PlayerController.updateInventory(ply, wep) end)
    hook.Add("PlayerDroppedWeapon", "PlayerController:UpdateTargetInventory", PlayerController.updateInventory)
    hook.Add("PlayerSwitchFlashlight", "PlayerController:ControlFlashlight", PlayerController.controlFlashlight)
    hook.Add("WeaponEquip", "PlayerController:ItemPickedUp", PlayerController.itemPickedUp) --PlayerCanPickupItem
    hook.Add("PlayerAmmoChanged", "PlayerController:AmmoPickedUp", PlayerController.ammoPickedUp)

    --hook.Add("TTT2CanOrderEquipment", "PlayerController:PreventEquipmentOrder", PlayerController.preventEquipmentOrder)

    self.sprintEnabled = GetConVar( "ttt2_sprint_enabled" )
    self.maxSprintMul = GetConVar( "ttt2_sprint_max" )

    -- replace receiver for Equipment ordering
    --net.Receive("TTT2OrderEquipment", PlayerController.NetOrderEquipmentOverride)
    --net.Receive("ttt2_switch_weapon", PlayerController.PickupWeaponOverride)
    --net.Receive("TTT2SprintToggle", PlayerController.SprintToggleOverride)

    -- Define Tables
    c_ply.controller = self
    self.c_ply = c_ply

    t_ply.controller = self
    self.t_ply = t_ply

    self.view_flag = view_flag
    self.net_flag  = net_flag

    -- Make Transition
    --self.spectator = StartPCSpectate(c_ply, t_ply, realFirstPerson)

    hook.Run("PlayerController:StartTransition", self.c_ply, self.t_ply)


    -- Send initial information to the clients
    PlayerController.NetSend(self.c_ply, {
        mode = PC_SV_START,
        player = self.t_ply,
        view_flag = view_flag,
        net_flag = net_flag,
        controlling = true,
    })

    PlayerController.NetSend(self.t_ply, {
        mode = PC_SV_START,
        player = self.c_ply,
        net_flag = net_flag,
        controlling = false
    })

    -- Set Some Network Variables:
    --self.t_ply:SetNWBool("PlayerController_Controlled", true)

    -- make controlling player unarmed
    --self.previous_wep = self.c_ply:GetActiveWeapon()
    --local unarmed = self.c_ply:GetWeapon("weapon_ttt_unarmed")
    --self.c_ply:SetActiveWeapon(unarmed)

    self.updateInventory(self.t_ply)

    -- update missing target player information on the controlling client
    timer.Create("UpdatePlayerInformation", 0.1, 0, function ()

        local wep = self.t_ply:GetActiveWeapon()

        local ammo = 0
        local clip = -1

        if IsValid(wep) then
            ammo = self.t_ply:GetAmmoCount(wep:GetPrimaryAmmoType())
            clip = wep:Clip1()
        end
        --
        --print("Wep:", wep, "ammotype:", ammotype, "ammo:", ammo, "clip:", clip)
        --print("sprintProgress:", self.t_ply.sprintProgress)

        --print("Sending Player:", self.t_ply, "to Client:", self.t_ply:GetSubRole())
        PlayerController.NetSend(self.c_ply, {
            mode = PC_SV_PLAYER,
            player = self.t_ply,
            role = self.t_ply:GetSubRole(),
            credits = self.t_ply:GetCredits(),
            drowning = nil,
            armor = self.t_ply.armor,
            clip = clip,
            ammo = ammo,
        })
    end)
end

function PlayerController:EndControl()
    -- Add Controlling Hooks
    if self.isActive then

        -- Delete Player Information Timer
        timer.Remove("UpdatePlayerInformation")
        -- Reset back to origional function
        --net.Receive("ttt2_switch_weapon", PlayerController.PickupWeaponDefault)

        -- reset previous wepon 
        -- TODO: not needed if attacking is disabled
        --self.c_ply:SetActiveWeapon(self.previous_wep)
        --self.previous_wep = nil

        hook.Remove("StartCommand", "PlayerController:OverrideCommands")
        hook.Remove("DoAnimationEvent", "PlayerController:PreventAnimations")
        --hook.Remove("SetupMove", "PlayerController:SetupMove")
        hook.Remove("FinishMove", "PlayerController:DisableControllerMovment")

        hook.Remove("PlayerDeath", "PlayerController:PlayerDied")
        hook.Remove("PlayerSwitchWeapon", "PlayerController:DisableWeaponSwitch")
        hook.Remove("WeaponEquip", "PlayerController:UpdateTargetInventory")
        hook.Remove("PlayerDroppedWeapon", "PlayerController:UpdateTargetInventory")
        hook.Remove("PlayerSwitchFlashlight", "PlayerController:ControlFlashlight")
        hook.Remove("WeaponEquip", "PlayerController:ItemPickedUp")
        hook.Remove("PlayerAmmoChanged", "PlayerController:AmmoPickedUp")

        --hook.Remove("TTT2CanOrderEquipment", "PlayerController:PreventEquipmentOrder")

        -- DO Some transition
        hook.Run("PlayerController:StopTransition", self.c_ply, self.t_ply)

        -- Send Message to CLients
        PlayerController.NetSend(self.c_ply, {
            mode = PC_SV_END,
        })

        PlayerController.NetSend(self.t_ply, {
            mode = PC_SV_END,
        })

        -- Rest Network Variables
        self.c_ply:SetNWInt("PlayerController_Buttons", 0)
        self.c_ply:SetNWInt("PlayerController_Impluse", 0)

        --self.t_ply:SetNWBool("PlayerController_Controlled", false) --TODO: Brauche ich das überhaupt?

        --self.c_ply:SetCanWalk(true)

        -- Reset Entries in Players:
        self.c_ply.controller = nil
        self.t_ply.controller = nil

        self.c_ply = nil
        self.t_ply = nil

        --self.updateSprintOverriden = false

        self.isActive = nil
    end
end

-----------------------------------
------ Controller Funktions -------
-----------------------------------

-- 1. StartCommand     -> overrideCommands (SERVER)  -- Transfers Movement data to client and delets input
-- 2. CreateMove                           (CLIENT)  -- Not used (before send to server)
-- 3. CalcMainActivity -> preventAnimation (SHARED)  -- Prevents any animations being played for c_ply -> return nil
-- 4. SetupMove        -> SetupMove        (SERVER)  -- Allows to disable 
-- 5. Move

-- coverride Commands
function PlayerController.overrideCommands(ply, cmd)
    -- Override for the controling Person
    if ply:IsController() then
        --if ply.controller.net_flag == PC_CLIENTSIDE then return end

        --local c_ply = ply
        --local t_ply = ply.controller.t_ply

        -- c_ply:SetNWInt("PlayerController_Buttons", cmd:GetButtons())
        -- c_ply:SetNWInt("PlayerController_Impluse", cmd:GetImpulse())

        -- c_ply.controller["ForwardMove"] = cmd:GetForwardMove()
        -- c_ply.controller["SideMove"] = cmd:GetSideMove()
        -- c_ply.controller["UpMove"] = cmd:GetUpMove()

        -- c_ply.controller["MouseWheel"] = cmd:GetMouseWheel()
        -- c_ply.controller["MouseX"] = cmd:GetMouseX()
        -- c_ply.controller["MouseY"] = cmd:GetMouseY()

        --local cmd = hook.Run("PlayerController:overrideControllerCommands")

        cmd:ClearMovement()
        cmd:ClearButtons()


    --------- TODO: OPTIMIZE

    -- Override for the controlled Person
    elseif ply:IsControlled() then
        if ply.controller.net_flag == PC_CLIENTSIDE then return end

        --print("Applying Commands Serverside")

        ply.controller:targetMove(cmd)

    --     local t_ply = ply
    --     local c_ply = ply.controller.c_ply
    --     local commands = {}
    --     local flag = false

    --     cmd:ClearButtons()
    --     cmd:ClearMovement()

    --     -- write commands you want to handle yourself
    --     -- return true to skip standardhanling of remaining inputs
    --     -- do:   commands = t_ply (to only take commands of target Player)
    --     --       commands = c_ply (to only take comands of controlling Player)   
    --     commands, flag = hook.Run("PlayerController:OverrideTargetCommands", c_ply, t_ply, commands, ply.controller.net_flag)
        
    --     if flag == false then
    --         -- do some standard input handling
    --         --print("Do standrad input handling")
    --         local angle = t_ply:EyeAngles()
    --         --print("angle: ", c_ply["CameraAngles"], angle)
    
    --         angle.pitch  = math.Clamp((c_ply["CameraAngles"] or angle).pitch + (t_ply["MouseY"] or 0) * 0.01, -85, 85) -- todo: es könnte sein, dass das nicht funktioniert
    --         angle.yaw    = (c_ply["CameraAngles"] or angle).yaw              - (t_ply["MouseX"] or 0) * 0.01           --       da auf dem Client eine andere Richtung berechnet wird.

    --         commands["CameraAngles"] = commands["CameraAngles"] or angle
    --         commands["Buttons"]      = commands["Buttons"]      or ((t_ply["Buttons"] or 0)     + (c_ply["Buttons"] or 0))
    --         commands["Impulse"]      = commands["Impulse"]      or ((t_ply["Impulse"] or 0)     + (c_ply["Impulse"] or 0))
    --         commands["ForwardMove"]  = commands["ForwardMove"]  or ((t_ply["ForwardMove"] or 0) + (c_ply["ForwardMove"] or 0))
    --         commands["SideMove"]     = commands["SideMove"]     or ((t_ply["SideMove"] or 0)    + (c_ply["SideMove"] or 0))
    --         commands["UpMove"]       = commands["UpMove"]       or ((t_ply["UpMove"] or 0)      + (c_ply["UpMove"] or 0))
    --         commands["MouseWheel"]   = commands["MouseWheel"]   or ((t_ply["MouseWheel"] or 0)  + (c_ply["MouseWheel"] or 0))
    --         commands["MouseX"]       = commands["MouseX"]       or ((t_ply["MouseX"] or 0)      + (c_ply["MouseX"] or 0))
    --         commands["MouseY"]       = commands["MouseY"]       or ((t_ply["MouseY"] or 0)      + (c_ply["MouseY"] or 0))
    --     else
    --         --print("Skip standard handling")
    --     end


    --     -- -- only take t_ply commands
    --     -- if result != nil and result == false then
    --     --     commands["CameraAngles"] = c_ply["CameraAngles"] or t_ply:EyeAngles()
    --     --     commands["Buttons"]      = c_ply["Buttons"]      or 0
    --     --     commands["Impulse"]      = c_ply["Impulse"]      or 0
    --     --     commands["ForwardMove"]  = c_ply["ForwardMove"]  or 0
    --     --     commands["SideMove"]     = c_ply["SideMove"]     or 0
    --     --     commands["UpMove"]       = c_ply["UpMove"]       or 0
    --     --     commands["MouseWheel"]   = c_ply["MouseWheel"]   or 0
    --     --     commands["MouseX"]       = c_ply["MouseX"]       or 0
    --     --     commands["MouseY"]       = c_ply["MouseY"]       or 0

    --     -- -- only take c_ply commands
    --     -- elseif result == true then
    --     --     commands["CameraAngles"] = c_ply["CameraAngles"] or t_ply:EyeAngles()
    --     --     commands["Buttons"]      = c_ply["Buttons"]      or 0
    --     --     commands["Impulse"]      = c_ply["Impulse"]      or 0
    --     --     commands["ForwardMove"]  = c_ply["ForwardMove"]  or 0
    --     --     commands["SideMove"]     = c_ply["SideMove"]     or 0
    --     --     commands["UpMove"]       = c_ply["UpMove"]       or 0
    --     --     commands["MouseWheel"]   = c_ply["MouseWheel"]   or 0
    --     --     commands["MouseX"]       = c_ply["MouseX"]       or 0
    --     --     commands["MouseY"]       = c_ply["MouseY"]       or 0
    --     -- end 

    --     --if not IsValid(c_ply) then return end

    --     -- cmd:SetButtons(c_ply:GetNWInt("PlayerController_Buttons", 0))
    --     -- cmd:SetImpulse(c_ply:GetNWInt("PlayerController_Impluse", 0))

    --     --print("commands:", commands["CameraAngles"], "c_ply", c_ply["CameraAngles"])

    --     -- TODO, das muss bearbeitet werden, um eine Überlagerung von Comands zu ermöglichen
    --     t_ply:SetEyeAngles(commands["CameraAngles"] or t_ply:EyeAngles())

    --     cmd:SetButtons(commands["Buttons"] or 0)
    --     cmd:SetImpulse(commands["Impulse"] or 0)

    --     cmd:SetForwardMove(commands["ForwardMove"] or 0)
    --     cmd:SetSideMove(commands["SideMove"] or 0)
    --     cmd:SetUpMove(commands["UpMove"] or 0)

    --     cmd:SetMouseWheel(commands["MouseWheel"] or 0)
    --     cmd:SetMouseX(commands["MouseX"] or 0)
    --     cmd:SetMouseY(commands["MouseY"] or 0)
    end
end


-- Terminates PlayerController if t_ply or c_ply dies
function PlayerController.playerDied(victim, inflictor, attacker)
    if victim:IsControlled() then
        victim.controller:EndControl()
    elseif victim:IsController() then
        -- TODO: Hier vielleicht etwas machen
        return
    end
end

-- Update Target Inventory:
function PlayerController.updateInventory(ply, wep)
    if ply:IsControlled() then
        local c_ply = ply.controller.c_ply
        -- TODO: Error with Nick() not valid!)
        --print("SERVER: Updating Inventory:", ply:Nick(), "Hat ", wep, "aufgehoben. Send to:", ply.controller.c_ply:Nick())
        timer.Simple(0.05, function()
            PlayerController.NetSend(c_ply, {
                mode = PC_SV_INVENTORY,
                player = ply,
                inventory = ply:GetInventory()
            })
        end)
    end
end

-- Weapon / Item Pickup
function PlayerController.itemPickedUp( item, ply )
    if ply:IsControlled() then
        -- print("Send message to client")

        if items.IsItem(item.id) then
            PlayerController.NetSend(ply.controller.c_ply, {
                mode = PC_SV_PICKUP,
                player = ply,
                type = PC_PICKUP_ITEM,
                item = item
            })
        else
            PlayerController.NetSend(ply.controller.c_ply, {
                mode = PC_SV_PICKUP,
                player = ply,
                type = PC_PICKUP_WEAPON,
                weapon = item
            })
        end
    end
end

-- Ammo Pickup
function PlayerController.ammoPickedUp(ply, ammoID, oldCount, newCount)
    if ply:IsControlled() then
        local difference = newCount - oldCount
        if difference > 0 then
           local name = game.GetAmmoName( ammoID )
            PlayerController.NetSend(ply.controller.c_ply, {
                mode = PC_SV_PICKUP,
                player = ply,
                type = PC_PICKUP_AMMO,
                ammo = name,
                count = difference
            })
        end
    end
end

--- Get Command Data from c_ply and apply commands to t_ply
net.Receive("PlayerController:NetCommands", function (len, ply)
    if ply:IsController() or ply:IsControlled() then

        --local controller = calling_ply --.controller
        local old = ply["CameraAngles"]
        ply["CameraAngles"] = net.ReadAngle() -- or ply["CameraAngles"]
        --print("old:", old, "\tnew", ply["CameraAngles"])
        --print("cmds:", ply:Nick(), ply["CameraAngles"])

        ply["Buttons"] = net.ReadUInt(25) or 0
        ply["Impluse"] = net.ReadUInt(8) or 0

        ply["ForwardMove"] = net.ReadInt(15) or 0
        ply["SideMove"] = net.ReadInt(15) or 0
        ply["UpMove"] = net.ReadInt(15) or 0

        ply["MouseWheel"] = net.ReadInt(6) or 0
        ply["MouseX"] = net.ReadInt(14) or 0
        ply["MouseY"] = net.ReadInt(14) or 0

        if ply.controller.net_flag == PC_CLIENTSIDE and ply:IsController() then
            --print("Sending Information to the target player")
            net.Start("PlayerController:ControllerCommands")
                net.WriteAngle(ply["CameraAngles"] or ply:EyeAngles())

                net.WriteUInt(ply["Buttons"] or 0, 25)     -- 25: +33554431 (needs: 16777216)
                net.WriteUInt(ply["Impluse"] or 0, 8)      --  8: +255      (needs: +204)

                net.WriteInt(ply["ForwardMove"] or 0, 15)  -- 15: +-16384   (needs: +-10000)
                net.WriteInt(ply["SideMove"] or 0, 15)     -- 15: +-16384   (needs: +-10000)
                net.WriteInt(ply["UpMove"] or 0, 15)       -- 15: +-16384   (needs: +-10000)

                net.WriteInt(ply["MouseWheel"] or 0, 6)    --  6: +-31      (needs: +-25)
                net.WriteInt(ply["MouseX"] or 0, 14)       -- 14: +-8191    (needs: +-5000)
                net.WriteInt(ply["MouseY"] or 0, 14)       -- 14: +-8191    (needs: +-5000)
            net.Send(ply.controller.t_ply)
        end
    end
end)

--- Communication

net.Receive("PlayerController:ControlToSV", function (len, ply)
    local mode = net.ReadUInt(3)

    -- If message from Controlling Player
    if ply:IsController() then

        local t_ply = ply.controller.t_ply

        -- Select Weapon
        if mode == PC_CL_WEAPON then
            local wep = net.ReadString()

            --print("Select Weapon:", wep)

            t_ply:SelectWeapon(wep)

        -- Drop Weapon
        elseif mode == PC_CL_DROP_WEAPON then
            local wep = net.ReadEntity()

            if wep.AllowDrop then
                --print("Drop Weapon.", wep)

                t_ply:DropWeapon(wep)
                -- TODO: Wird eigentlich bei Drop Weapon event ausgeführt. 
                -- Funktioniert aber noch nicht richtig.
                --PlayerController.updateInventory(t_ply)
            end

        -- Request Inventory:
        elseif mode == PC_CL_INVENTORY then
            --print("NetCl: Send inventory of Player: " .. t_ply:Nick() .. " to player: ", c_ply:Nick())
            PlayerController.updateInventory(t_ply)

        elseif mode == PC_CL_MESSAGE then
            print("Getting Message from wrong player")

        end

    -- if message from Target Player -- TODO: REMOVE
    -- Die Nachricht vom Bot kommt nicht an.
    elseif ply:IsControlled() then
        print("NetCl from t_ply.")
        if mode == PC_CL_MESSAGE then
            print("Got Message from Target Player:")
        end
    end
end)


-- Override Server Communication from TTT2 Standard

-- Override Equipment Ordering to Forward to t_ply
-- ATTENTION: THIS changes the definition of the 
-- function PlayerController.NetOrderEquipmentOverride(len, ply)
--     local cls = net.ReadString()

--     if PlayerController.t_ply and ply == PlayerController.c_ply then
--         print("OrdereEquipment custom from:", ply:Nick())

--         concommand.Run( PlayerController.t_ply, "ttt_order_equipment", {cls} )
--     else
--         -- TODO: Error with passiv items!
--         concommand.Run( ply, "ttt_order_equipment", {cls}  )
--     end
-- end


--net.Receive("ttt2_switch_weapon", function(_, ply)

-- function PlayerController.PickupWeaponOverride(_, ply)
--     print("overridden Weapon Pickup")
--     if PlayerController.t_ply and ply == PlayerController.c_ply then
--         ply = PlayerController.t_ply
--     end

--     -- player and wepaon must be valid
--     if not IsValid(ply) or not ply:IsTerror() or not ply:Alive() then return end

--     -- handle weapon switch
--     local tracedWeapon = ply:GetEyeTrace().Entity

--     if not IsValid(tracedWeapon) or not tracedWeapon:IsWeapon() then return end

--     -- do not pickup weapon if too far away
--     if ply:GetPos():Distance(tracedWeapon:GetPos()) > 100 then return end

--     ply:SafePickupWeapon(tracedWeapon, nil, nil, true) -- force pickup and drop blocking weapon as well
-- end

-- -- Sprind override
-- function PlayerController.SprintToggleOverride(_, ply)
--     if PlayerController.t_ply and ply == PlayerController.c_ply then
--         ply = PlayerController.t_ply
--     end
--     -- sprintEnabled:GetBoll()
--     if not PlayerController.sprintEnabled:GetBool() or not IsValid(ply) then return end

--     local bool = net.ReadBool()

--     ply.oldSprintProgress = ply.sprintProgress
--     ply.sprintMultiplier = bool and (1 + PlayerController.maxSprintMul:GetFloat()) or nil
--     ply.isSprinting = bool
-- end

-- TODO: REMOVE Default PICKUP
-- function PlayerController.PickupWeaponDefault(_, ply)
    
--     -- player and wepaon must be valid
-- 	if not IsValid(ply) or not ply:IsTerror() or not ply:Alive() then return end

-- 	-- handle weapon switch
-- 	local tracedWeapon = ply:GetEyeTrace().Entity

-- 	if not IsValid(tracedWeapon) or not tracedWeapon:IsWeapon() then return end

-- 	-- do not pickup weapon if too far away
-- 	if ply:GetPos():Distance(tracedWeapon:GetPos()) > 100 then return end

-- 	ply:SafePickupWeapon(tracedWeapon, nil, nil, true) -- force pickup and drop blocking weapon as well
-- end




-- local function ConCommandOrderEquipment(ply, cmd, args)
-- 	if #args ~= 1 then return end

-- 	OrderEquipment(ply, args[1])
-- end
-- concommand.Add("ttt_order_equipment", ConCommandOrderEquipment)


-- function PlayerController.finishMove(ply, mv)
--     if ply.controller and ply.controller["t_ply"]  then
--         print("finish Move")
--         return true
--     end
-- end

-- function GM:Move(ply, mv)
--     return true
--     -- if ply.controller and ply.controller["t_ply"] then
--     --     return true
--     -- end
-- end


