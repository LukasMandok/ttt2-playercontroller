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

function PlayerController:__init(tbl)
    self:StartControl(tbl)
end

local TryT = LANG.TryTranslation
local ParT = LANG.GetParamTranslation


-------------- Overriding Network Communication --------------

local ply_meta = FindMetaTable("Player")
local ent_meta = FindMetaTable("Entity")

ply_meta.OldIsSpec      = ply_meta.OldIsSpec or ply_meta.IsSpec
ply_meta.OldSteamID64  = ply_meta.OldSteamID64  or ply_meta.SteamID64
ent_meta.OldGetForward = ent_meta.OldGetForward or ent_meta.GetForward

WSWITCH.OldConfirmSelection = WSWITCH.OldConfirmSelection or WSWITCH.ConfirmSelection

OldLocalPlayer = OldLocalPlayer or LocalPlayer

-- Override Functions for the controlling Player
function PlayerController:__overrideFunctions( flag )

    local t_ply = self.t_ply
    local c_ply = self.c_ply
    --local t_ply_meta = getmetatable(t_ply)

    -- start override
    if flag == true then
        -- Local Player
        LocalPlayer = function()
            if t_ply == nil then
                return OldLocalPlayer()
            else
                return t_ply
            end
        end

        -- -- WSITCH 
        WSWITCH.ConfirmSelection = function() end

        -- -- SteamID for Bots
        if t_ply:IsBot() then
            --print("overriding SteamID64 for:", t_ply:Nick())
            --print("\nOld SteamID64:", t_ply:SteamID64())

            --player_manager.SetPlayerClass(t_ply, "t_ply")
            ply_meta.SteamID64 = function(slf)
                --print("slf:", slf)
                --print("old:", slf:OldSteamID64())
                if slf == t_ply then
                    return c_ply:OldSteamID64()
                else
                    return slf:OldSteamID64()
                end
                -- TODO: For some reaseon the game crashes with that!!
                --return OldLocalPlayer():SteamID64()
            end
            --print("PlayerClass:", player_manager.GetPlayerClass(t_ply))
            --PrintTable( baseclass.Get( "t_ply" ) )
            --print("New SteamID64:", t_ply:SteamID64())
            --print("DisplayName:", t_ply.DisplayName)
        end

        --override spectator function:
        ply_meta.IsSpec = function(slf)
            if t_ply == nil then
                return slf:OlIsSpec()
            else
                return t_ply:OldIsSpec()
            end
        end

        -- -- Forward function for clients
        ent_meta.GetForward = function(slf)
            if slf == t_ply then
                local angle = slf:EyeAngles()
                angle[3] = 0
                return angle:Forward()
            else
                return slf:OldGetForward()
            end
        end

    -- reset back to previous
    else
        --LocalPlayer = OldLocalPlayer
        LocalPlayer = OldLocalPlayer

        -- reset WSWITCH
        WSWITCH.ConfirmSelection = WSWITCH.OldConfirmSelection

        -- -- -- reset SteamID64 functino for bots
        if t_ply:IsBot() then
            --player_manager.ClearPlayerClass(t_ply)
            ply_meta.SteamID64 = ply_meta.OldSteamID64
            -- = function(self)
            --     return nil
            -- end
        end

        -- reset ALive function
        ply_meta.IsSpec = ply_meta.OldIsSpec

        -- -- reset GetForward function 
        --if ent_meta.GetForward != ent_meta.OldGetForward then
        ent_meta.GetForward = ent_meta.OldGetForward
        --end
    end
end

-- HARDCODED!!!
local function HandleArmorStatusIcons(ply)
    -- removed armor
    if ply.armor <= 0 then
        if STATUS:Active("ttt_armor_status") then
            STATUS:RemoveStatus("ttt_armor_status")
        end

        return
    end

    -- check if reinforced
    local icon_id = 1

    if not GetGlobalBool("ttt_armor_classic", false) then
        icon_id = ply:ArmorIsReinforced() and 2 or 1
    end

    -- normal armor level change (update)
    if STATUS:Active("ttt_armor_status") then
        STATUS:SetActiveIcon("ttt_armor_status", icon_id)

        return
    end

    -- added armorc if not active
    STATUS:AddStatus("ttt_armor_status", icon_id)
end

-----------------------------------------------------
------------------- Communication -------------------
-----------------------------------------------------

function PlayerController.SendControlToSV( mode, arg1, arg2 )
    net.Start("PlayerController:ControlToSV")
        net.WriteUInt(mode, 3)

        if mode == PC_CL_WEAPON then
            net.WriteString(arg1)

        elseif mode == PC_CL_DROP_WEAPON then
            net.WriteEntity(arg1)

        elseif mode == PC_CL_INVENTORY then
            -- nothing more
        end

    net.SendToServer()
end

-- Receive essage 
net.Receive("PlayerController:ControlToCL", function (len)
    local ply = OldLocalPlayer()
    if not IsValid(ply) then return end
    local tbl = net.ReadTable()

    -- START
    if tbl.mode == PC_SV_START then
        --MsgC(Color(255, 64, 64), "[PLAYER CONTROLLER] ", Color(198, 198, 198), tbl.log.."\n")

        -- Set the table to the player
        PlayerController(tbl)

    -- END
    elseif tbl.mode == PC_SV_END then
        local controller = ply.controller

        if not controller then
            print("Contoler not valid for:", ply:Nick(), controller)
            return
        end

        print("Controller is valid and Terminating now:", controller.camera)
        controller:EndControl()

    -- MESSAGE FROM SERVER
    elseif tbl.mode == PC_SV_MESSAGE then
        -- TODO: Popup mit Inhalt und Dauer
        print("received message from the server")

    -- Inventory Update of Target Player for Controlling Player
    elseif tbl.mode == PC_SV_INVENTORY then
        --print("CLIENT: Update Inventory")
        if ply:IsController() then
            ply.controller["t_ply"].inventory = tbl.inventory
            -- print("\n\nNew Inventory: ")
            -- PrintTable(ply.controller["t_ply"].inventory)
            -- print("Actual Inventory: ")
            -- PrintTable(ply.controller["t_ply"]:GetInventory())
        end

    elseif tbl.mode == PC_SV_PLAYER then
        --print("Client: Update Target Information", ply.controller, ply.controller["t_ply"])
        if ply:IsController(tbl.player) then
            local t_ply = ply.controller["t_ply"] 

            t_ply:SetRole(tbl.role)
            t_ply.equipment_credits = tbl.credits
            --ply.controller["t_ply"].sprintProgress = tbl.sprintProgress
            --ply.controller["t_ply"].oldSprintProgress = tbl.sprintProgress

            if tbl.armor and t_ply.armor ~= tbl.armor then
                t_ply.armor = tbl.armor
                HandleArmorStatusIcons(t_ply)
            end

            local wep = t_ply:GetActiveWeapon()
            -- local clip = tbl.clip
            -- local ammo = tbl.ammo
            -- print("ammo:", ammo, "clip:", clip)
            if IsValid(wep) then
                --print("Valid weapon -> set ammo and clip count")
                t_ply:SetAmmo( tbl.ammo,  wep:GetPrimaryAmmoType() )
                t_ply:GetActiveWeapon():SetClip1(tbl.clip)
            end

            --print("Role to set:", role)
            --print("Role of t_ply:", ply.controller["t_ply"]:GetSubRole())
        end
    elseif tbl.mode == PC_SV_PICKUP then
        if ply:IsController(tbl.player) then

            if tbl.type == PC_PICKUP_WEAPON then
                GAMEMODE:HUDWeaponPickedUp(tbl.weapon)
                --gamemode.Call("HUDWeaponPickedUp", tbl.weapon)

            elseif tbl.type == PC_PICKUP_ITEM then
                GAMEMODE:HUDItemPickedUp(tbl.item)
                --gamemode.Call("HUDItemPickedUp", tbl.item)

            elseif tbl.type == PC_PICKUP_AMMO then
                GAMEMODE:HUDAmmoPickedUp(tbl.ammo, tbl.count)
                --gamemode.Call("HUDAmmoPickedUp", tbl.ammo, tbl.count)
            end

        end
    end
end)

net.Receive("PlayerController:ControllerCommands", function (len)
    if not OldLocalPlayer():IsControlled() then return end
    local c_ply = OldLocalPlayer().controller.c_ply 

    print("Receive Controller Commands:", c_ply:Nick())

    c_ply["CameraAngles"] = net.ReadAngle() 

    c_ply["Buttons"] = net.ReadUInt(25)
    c_ply["Impluse"] = net.ReadUInt(8)

    c_ply["ForwardMove"] = net.ReadInt(15)
    c_ply["SideMove"] = net.ReadInt(15)
    c_ply["UpMove"] = net.ReadInt(15)

    c_ply["MouseWheel"] = net.ReadInt(6)
    c_ply["MouseX"] = net.ReadInt(14)
    c_ply["MouseY"] = net.ReadInt(14)
end)

function PlayerController.NetSendCommands(ply, cmd)
   
    local angles 
    -- controller + not lookaround -> camera angle
    if ply:IsController() and not ply.controller.camera.look_around then
        local camera = ply.controller.camera
        angles = camera:GetCorrectedAngles()
        --print("Camera Angles", angles)
    
    -- controler + lookaround -> t_ply Angle()
    elseif ply:IsController() and ply.controller.camera.look_around then
        --print("t_ply:EyeAngles")
        angles = ply.controller.t_ply:EyeAngles()
    
    -- target -> input Angle
    elseif ply:IsControlled() then
        angles = cmd:GetViewAngles()

        --angles = ply:EyeAngles()
        --angles.pitch  = math.Clamp(angles.pitch + cmd:GetMouseY() * 0.01, -85, 85)
        --angles.yaw    = angles.yaw              - cmd:GetMouseX() * 0.01
        --print("t_ply cmd:GetViewAngles", angles)
    end
    
    --get commands of the local player
    ply["CameraAngles"] = angles
    ply["Buttons"] = cmd:GetButtons()
    ply["Impluse"] = cmd:GetImpulse()

    ply["ForwardMove"] = cmd:GetForwardMove()
    ply["SideMove"] = cmd:GetSideMove()
    ply["UpMove"] = cmd:GetUpMove()

    ply["MouseWheel"] = cmd:GetMouseWheel()
    ply["MouseX"] = cmd:GetMouseX()
    ply["MouseY"] = cmd:GetMouseY()
    --print("MouseX:", cmd:GetMouseX(), ply:Nick())

    if (not ply:IsController()) and ply.controller.net_flag == PC_CLIENTSIDE then 
        return
    end

    -- send comands to the server
    net.Start("PlayerController:NetCommands")
        net.WriteAngle(angles)

        net.WriteUInt(ply["Buttons"], 25)     -- 25: +33554431 (needs: 16777216)
        net.WriteUInt(ply["Impluse"] , 8)      --  8: +255      (needs: +204)

        net.WriteInt(ply["ForwardMove"], 15)  -- 15: +-16384   (needs: +-10000)
        net.WriteInt(ply["SideMove"], 15)     -- 15: +-16384   (needs: +-10000)
        net.WriteInt(ply["UpMove"], 15)       -- 15: +-16384   (needs: +-10000)

        net.WriteInt(ply["MouseWheel"], 6)    --  6: +-31      (needs: +-25)
        net.WriteInt(ply["MouseX"], 14)       -- 14: +-8191    (needs: +-5000)
        net.WriteInt(ply["MouseY"], 14)       -- 14: +-8191    (needs: +-5000)
    net.SendToServer()
--         -- c_ply.controller["ForwardMove"] = cmd:GetForwardMove()
--         -- c_ply.controller["SideMove"] = cmd:GetSideMove()
--         -- c_ply.controller["UpMove"] = cmd:GetUpMove()

--         -- c_ply.controller["MouseWheel"] = cmd:GetMouseWheel()
--         -- c_ply.controller["MouseX"] = cmd:GetMouseX()
--         -- c_ply.controller["MouseY"] = cmd:GetMouseY()
    
end

-----------------------------------------------------
----------------- Control Functions -----------------
-----------------------------------------------------

function PlayerController:StartControl(tbl)
    local ply = OldLocalPlayer()

    -- If controlling Player
    if tbl.controlling then
        print("Start new controlling")
        self.c_ply = ply
        self.t_ply = tbl.player

        self.c_ply.controller = self
        self.t_ply.controller = self

        self.view_flag = tbl.view_flag or PC_CAM_FIRSTPERSON
        self.net_flag  = tbl.net_flag  or PC_SERVERSIDE 


        -- create Camera
        self.camera = PlayerCamera(self.c_ply, self.t_ply, self.view_flag, self.net_flag)
        -- print("camera1:", self.camera)
        -- print("camera2:", c_ply.controller.camera)
        -- print("camera3:", self.c_ply.controller.camera)
        -- print("camera4:", t_ply.controller.camera)
        hook.Add("StartCommand", "PlayerController:ManageCommands", PlayerController.manageCommands)
        hook.Add("PlayerBindPress", "PlayerController:OverrideControllerBinds", PlayerController.overrideBinds)
        hook.Add("DoAnimationEvent", "PlayerController:PreventAnimations", PlayerController.preventAnimations) -- CalcMainActivity

        hook.Add("Move", "PlayerController:ButtonControls", PlayerController.buttonControls)
        --hook.Add("SetupMove", "PlayerController:SetupMove", PlayerController.preventAttacking)
        hook.Add("FinishMove", "PlayerController:DisableControllerMovment", PlayerController.disableMovment)
        hook.Add("PlayerSwitchWeapon", "PlayerController:DisableWeaponSwitch", PlayerController.disableWeaponSwitch)
        --hook.Add("InputMouseApply", "PlayerController:DisableControllerMouse", PlayerController.disableMouse)

        hook.Add("CalcView", "PlayerController:CameraView", function(calling_ply, pos, angles, fov, znear, zfar)
            local view = {origin = pos, angles = angles, fov = fov, znear = znear, zfar = zfar, drawviewer = true}
            if self.camera:CalcView( view, calling_ply, true ) then return view end -- ply:IsPlayingTaunt()
        end)

        hook.Add("CreateMove","PlayerController:CameraMovment",function(cmd)
            self.camera:CreateMove( cmd, self.c_ply, true)
        end)

        hook.Add("HUDPaint", "PlayerController:DrawHelpHUD", PlayerController.drawHelpHUD)
        hook.Add("TTTRenderEntityInfo", "PlayerController:DrawTargetID", PlayerController.drawTargetID)
        hook.Add("HUDWeaponPickedUp", "PlayerController:WeaponPickupNotification", PlayerController.pickupNotification)
        hook.Add("HUDItemPickedUp", "PlayerController:ItemPickupNotification", PlayerController.pickupNotification)
        hook.Add("HUDAmmoPickedUp", "PlayerController:AmmoPickupNotification", PlayerController.pickupNotification)

        self:__overrideFunctions(true)

        self.t_ply.armor = self.t_ply.armor or 0
        HandleArmorStatusIcons(self.t_ply)

        -- Override Sprint Update
        self.updateSprintOverriden = true
        self:addHUDHelp()

    -- If the controlled Player
    else
        self.c_ply = tbl.player
        self.t_ply = ply

        self.c_ply.controller = self
        self.t_ply.controller = self

        self.net_flag  = tbl.net_flag or PC_SERVERSIDE 

        -- TODO: Disable all commands / or maybe not
        hook.Add("StartCommand", "PlayerController:ManageCommands", PlayerController.manageCommands)
    	--hook.Add( "InputMouseApply", "PlayerController:TargetMouseInput", PlayerController.targetMouseInput)

        if self.net_flag == PC_SERVERSIDE then
            hook.Add( "InputMouseApply", "PlayerController:TargetMouseInput", PlayerController.targetMouseInput)
        elseif self.net_flag == PC_CLIENTSIDE then
            hook.Add("CreateMove", "PlayerController:TargetMovment", PlayerController.createTargetMove)

            -- hook.Add("CalcView", "PlayerController:CalcTargetView", function(calling_ply, pos, angles, fov, znear, zfar)
            --     local view = {origin = pos, angles = angles, fov = fov, znear = znear, zfar = zfar, drawviewer = true}
            --     if PlayerController.calcTargetView( view, calling_ply ) then return view end -- ply:IsPlayingTaunt()
            -- end)
        end

    end
end

function PlayerController:EndControl()
    local t_ply = self.t_ply
    local c_ply = self.c_ply

    --TODO: Distinguish between c_ply and t_ply 

    hook.Remove("DoAnimationEvent", "PlayerController:PreventAnimations")
    --hook.Remove("SetupMove", "PlayerController:SetupMove")
    hook.Remove("FinishMove", "PlayerController:DisableControllerMovment")
    hook.Remove("PlayerSwitchWeapon", "PlayerController:DisableWeaponSwitch")

    hook.Remove("Move", "PlayerController:ButtonControls")

    hook.Remove("CalcView", "PlayerController:CameraView")
    hook.Remove("CreateMove", "PlayerController:CameraMovment")

    --hook.Remove("CalcView", "PlayerController:CalcTargetView") -- target
    hook.Remove("CreateMove","PlayerController:TargetMovment") -- target
    hook.Remove( "InputMouseApply", "PlayerController:TargetMouseInput")

    hook.Remove("StartCommand", "PlayerController:ManageCommands") -- both
    hook.Remove("PlayerBindPress", "PlayerController:OverrideControllerBinds")
    hook.Remove("PlayerBindPress", "PlayerController:DisableTargetBinds")

    hook.Remove("HUDPaint", "PlayerController:DrawHelpHUD")
    hook.Remove("TTTRenderEntityInfo", "PlayerController:DrawTargetID")
    hook.Remove("HUDWeaponPickedUp", "PlayerController:WeaponPickupNotification")
    hook.Remove("HUDItemPickedUp", "PlayerController:ItemPickupNotification")
    hook.Remove("HUDAmmoPickedUp", "PlayerController:AmmoPickupNotification")

    self:__overrideFunctions(false)

    -- back to previous Sprint update function
    self:removeHUDHelp()
    self.updateSprintOverriden = false

    c_ply.controller = nil
    t_ply.controller = nil

    self.c_ply = nil
    self.t_ply = nil

    self.camera:Stop()
    self.camera = nil

    -- Update Status of Armor Icon, at player change.
    HandleArmorStatusIcons(t_ply)
end


-----------------------------------------------------
---------------- Overriding Functions ---------------
-----------------------------------------------------

function PlayerController.manageCommands( ply, cmd )
    -- send commands to the server, before they are disabled
    PlayerController.NetSendCommands(ply, cmd)

    -- clear comands for the controller
    if ply:IsController() then
        cmd:ClearButtons()
        cmd:ClearMovement()

    -- clear comands for the target, if operated serverside
    elseif ply:IsControlled()  then --and ply.controller.net_flag == PC_SERVERSIDE
        cmd:ClearButtons()
        cmd:ClearMovement()
        --cmd:SetViewAngles(ply:EyeAngles())
        -- cmd:SetMouseX( 0 )
	    -- cmd:SetMouseY( 0 )
    end
end

-- TODO: Clientside prediction of mouse movment
function PlayerController.targetMouseInput(cmd, x, y, ang )
    cmd:SetMouseX( 0 )
	cmd:SetMouseY( 0 )
    return true
end

-- function PlayerController.calcTargetView(view, ply)
--     --if not ply:IsControlled() then return end#
--     print("focing player view:", ply:EyeAngles())
--     view.angles = ply:EyeAngles()
--     return true
-- end

function PlayerController.createTargetMove(cmd)
    local t_ply = OldLocalPlayer()

    --print("TargetMove:", t_ply:Nick(), "controlled:", t_ply:IsControlled(), t_ply.controller.net_flag)
    -- TODO: Das sollte nicht relevant sein
    if (not t_ply:IsControlled()) or t_ply.controller.net_flag == PC_SERVERSIDE then 
        return 
    end

    t_ply.controller:targetMove(cmd)

    -- local c_ply = t_ply.controller.c_ply

    -- print("Forcing player view:", LocalPlayer():EyeAngles())
    -- print("target Player, ForwardMove:", t_ply["ForwardMove"])
    -- print("controlling Player, Forward Move:", c_ply["ForwardMove"])

    -- local commands = {}

    -- cmd:ClearButtons()
    -- cmd:ClearMovement()

    -- commands["CameraAngles"] = c_ply["CameraAngles"] or t_ply:EyeAngles()
    -- commands["Buttons"]      = c_ply["Buttons"]      or 0
    -- commands["Impulse"]      = c_ply["Impulse"]      or 0
    -- commands["ForwardMove"]  = c_ply["ForwardMove"]  or 0
    -- commands["SideMove"]     = c_ply["SideMove"]     or 0
    -- commands["UpMove"]       = c_ply["UpMove"]       or 0
    -- commands["MouseWheel"]   = c_ply["MouseWheel"]   or 0
    -- commands["MouseX"]       = c_ply["MouseX"]       or 0
    -- commands["MouseY"]       = c_ply["MouseY"]       or 0

    -- -- TODO: Alter c_ply data with t_ply data
    -- if hook.Run("PlayerController:OverrideTargetCommands", c_ply, t_ply, cmd, commands) then return end

    -- --if not IsValid(c_ply) then return end

    -- -- cmd:SetButtons(c_ply:GetNWInt("PlayerController_Buttons", 0))
    -- -- cmd:SetImpulse(c_ply:GetNWInt("PlayerController_Impluse", 0))

    -- -- TODO, das muss bearbeitet werden, um eine Überlagerung von Comands zu ermöglichen
    -- t_ply:SetEyeAngles(commands["CameraAngles"])

    -- cmd:SetButtons(commands["Buttons"])
    -- cmd:SetImpulse(commands["Impulse"])

    -- cmd:SetForwardMove(commands["ForwardMove"] )
    -- cmd:SetSideMove(commands["SideMove"])
    -- cmd:SetUpMove(commands["UpMove"])

    -- cmd:SetMouseWheel(commands["MouseWheel"])
    -- cmd:SetMouseX(commands["MouseX"])
    -- cmd:SetMouseY(commands["MouseY"])

     return true
end

-- hook.Add( "InputMouseApply", "FreezeTurning", function( cmd )
-- 	-- cmd:SetMouseX( 0 )
-- 	-- cmd:SetMouseY( 0 )

-- 	return true
-- end )

-- -- Disable Binds for the target player    --  bind, pressed
-- local function targetTest( ply, cmd )

--     print("target Test")
--     PlayerController.NetSendCommands(ply, cmd)

--     cmd:ClearButtons()
--     cmd:ClearMovement()

--     --cmd:SetViewAngles( ply:EyeAngles() )
-- end

-- local function createMove(cmd)
--     cmd:SetViewAngles(LocalPlayer():EyeAngles())
-- end

-- hook.Add("StartCommand", "TargetTest", targetTest)

-- -- hook.Add("CalcView", "TargetTest", function(calling_ply, pos, angles, fov, znear, zfar)
-- --     local view = {origin = pos, angles = angles, fov = fov, znear = znear, zfar = zfar, drawviewer = true}
-- --     return PlayerController.calcTargetView( view, calling_ply ) -- ply:IsPlayingTaunt()
-- -- end)

-- hook.Add("CreateMove", "TargetTest", createMove)



--     print("Disable binds")
--    if not (ply:IsControlled()) then return end

--     -- If hook PlayerController:TargetMovment == true, target movment will not be disabled
--     if hook.Run("PlayerController:TargetMovment", ply, cmd) then
--         -- TODO: Send ViewAngles to the server
--         print("Return")
--         return 
--     end

--     cmd:ClearButtons()
--     cmd:ClearMovement()

--     cmd:SetViewAngles( ply:EyeAngles() )
--     ply:SetEyeAngles( ply:EyeAngles() )

--     --return true
-- end

-- hook.Add("PlayerController:TargetMovment", "AllowTargetMoving", function(ply, cmd)
--     return true
-- end)

-- send current weapon to server and activate HelpHUD
local function SelectWeapon( oldidx )
    local idx = WSWITCH.Selected

    -- if weapon did not change, do nothing
    if oldidx and oldidx == WSWITCH.Selected then return end

    local wep = WSWITCH.WeaponCache[idx]

    -- if wep.Initialize then
    --     wep:Initialize()
    -- end

    PlayerController.SendControlToSV(PC_CL_WEAPON, wep:GetClass())
end

-- Override Binds
function PlayerController.overrideBinds( ply, bind, pressed )
    if not ply:IsController() then return end

    local controller = ply.controller

    -- Next Weapon Slot / Camera Distance
    if bind == "invnext" and pressed then
        print("\n invnext")

        -- Change Camera Distance
        if input.IsKeyDown( KEY_LSHIFT ) then -- If shift is pressed, change camera distance
            controller.camera:ChangeOffset(10)

        -- Select Next Weapon
        else
            WSWITCH:SelectNext()
            SelectWeapon()
        end

        return true

    -- Previous Weapon Slot
    elseif bind == "invprev" and pressed then
        -- Change Camera Distance
        if input.IsKeyDown( KEY_LSHIFT ) then -- If shift is pressed, change camera distance
            controller.camera:ChangeOffset(-10)

        -- Select Previous Weapon
        else
            WSWITCH:SelectPrev()
            SelectWeapon()
        end

        return true

    -- Weapon Slot Number -> Select Slot 
    elseif string.sub(bind, 1, 4) == "slot" and pressed then
        local oldidx = WSWITCH.Selected
        --local inv = t_ply:GetInventory()
        local idx = tonumber(string.sub(bind, 5, - 1)) or 1

        WSWITCH:SelectSlot(idx)

        SelectWeapon(oldidx)

        -- if inv[idx][1] then
        --     --print("name:", inv[idx][1]:GetClass())
        --     PlayerController.SendControlToSV(PC_CL_WEAPON, inv[idx][1]:GetClass())
        --     return true
        -- end

        return true

    -- Q Button -> Drop Weapon
    elseif bind == "+menu" then
        PlayerController.SendControlToSV(PC_CL_DROP_WEAPON, controller.t_ply:GetActiveWeapon())
        return true

    end
end

-- Button Controls
function PlayerController.buttonControls(ply, mv)

    if not ply:IsController() then return end
        -- end Control

    local controller = ply.controller

    if not input.IsKeyDown(KEY_LSHIFT) and input.WasKeyPressed(KEY_BACKSPACE) then
        if controller.back_pressed == false then
            print("End Player Control")
            controller.back_pressed = true
            net.Start("PlayerController:NetControl")
                net.WriteUInt(PC_CL_END, 3)
            net.SendToServer()
        end

        return

    -- switch to next player
    elseif input.IsKeyDown(KEY_LSHIFT) and input.WasKeyPressed(KEY_BACKSPACE) then
        if controller.back_pressed == false then
            controller.back_pressed = true
            local t_i, c_i
            local alive_players = {}

            for i, p in pairs(player.GetAll()) do
                if p:Alive() then
                    alive_players[#alive_players + 1] = p
                    if p == controller.t_ply then t_i = #alive_players - 1
                    elseif p == controller.c_ply then c_i = #alive_players - 1 end
                end
            end
            
            if t_i and c_i then
                local n = #alive_players
                local next = (c_i ~= (t_i + 1) % n and (t_i + 1) % n or (t_i + 2) % n ) + 1

                print("n", n, "t:", t_i, "c", c_i, "next:", next)

                print("Switch through players.")

                net.Start("PlayerController:NetControl")
                    net.WriteUInt(PC_CL_SWITCH , 3)
                    net.WriteEntity(alive_players[next])
                net.SendToServer()
            else 
                print("target player: t_i =", t_i, "or controlling player: c_i =", c_i, "is not valid.")
            end
        end

        return

    -- switch to player in front
    elseif input.IsKeyDown(KEY_LSHIFT) and input.WasKeyPressed(KEY_E) then
        if controller.e_pressed == false then
            controller.e_pressed = true
            local ent = controller.camera:GetViewTargetEntity()

            if IsValid(ent) and ent:IsPlayer() and ent:Alive() then
                if ent == controller.c_ply then
                    print("Terminating Control")
                        net.Start("PlayerController:NetControl")
                        net.WriteUInt(PC_CL_END , 3)
                    net.SendToServer()
                else
                    print("Switching to player:", ent:Nick())
                        net.Start("PlayerController:NetControl")
                        net.WriteUInt(PC_CL_SWITCH , 3)
                        net.WriteEntity(ent)
                    net.SendToServer()
                end
            end
        end

        return

    -- look around without changing the eyeangle of t_ply
    elseif input.IsKeyDown(KEY_LSHIFT) and input.IsKeyDown(KEY_R) then
        controller.camera.look_around = true
        return
    end
    
    -- reset c_ply view
    if controller.camera.look_around == true then
        controller.camera.look_around = false
        controller.camera:ResetView()
    end

    controller.back_pressed = false
    controller.e_pressed = false

    return true

end

-- Draw Target ID to switch to other players:
function PlayerController.drawTargetID(tData)
    -- TODO: vieleicht unnötige Abfrage
    if not OldLocalPlayer():IsController() then return end

    local controller = OldLocalPlayer().controller

    local ent = tData:GetEntity()

    if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end

    local h_string, h_color = util.HealthToString(ent:Health(), ent:GetMaxHealth())

    if ent == controller.c_ply then
        tData:SetSubtitle(
            ParT("target_end_PC", {usekey = Key("+use", "USE"), name = ent:Nick()})
        )
    else
        tData:SetSubtitle(
            ParT("target_switch_PC", {usekey = Key("+use", "USE"), name = ent:Nick()})
        )
    end

    tData:AddDescriptionLine(
        TryT(h_string),
        h_color
    )
    --tData:SetKeyBinding("+use")
end

function PlayerController:removeHUDHelp()
    self.HUDHelp = nil
end

function PlayerController:addHUDHelp()
    self.HUDHelp = {
        lines = {},
        max_length = 0
    }

    self:addHUDHelpLine(TryT("help_hud_end_PC"), "BACK") -- Key("+reload", "R")
    self:addHUDHelpLine(TryT("help_hud_switch_PC"), "SHIFT", "E" ) -- Key("+reload", "R")
    self:addHUDHelpLine(TryT("help_hud_next_PC"), "SHIFT", "BACK" ) -- Key("+reload", "R")
    self:addHUDHelpLine(TryT("help_hud_look_around_PC"), "SHIFT", "R") --
end

function PlayerController:addHUDHelpLine(text, key1, key2)
    local width = draw.GetTextSize(text, "weapon_hud_help")

    self.HUDHelp.lines[#self.HUDHelp.lines + 1] = {text = text, key1 = key1, key2 = key2}
    self.HUDHelp.max_length = math.max(self.HUDHelp.max_length, width)
end


-- Draws the help Hud for the active weapon
-- and draws the control panel
function PlayerController.drawHelpHUD()
    if not OldLocalPlayer():IsController() then return end

    local controller = OldLocalPlayer().controller

    local wep = controller.t_ply:GetActiveWeapon()
    if IsValid(wep) then
        controller.t_ply:GetActiveWeapon():DrawHUD()
    end

    controller:drawHelp()
end

function PlayerController:drawHelp()
    if not self.HUDHelp then return end

    local data = self.HUDHelp
    local lines = data.lines
    local x = ScrW() * 0.66 + data.max_length * 0.5
    local y_start = ScrH() - 25
    local y = y_start
    local delta_y = 25
    local valid_icon = false

    for i = #lines, 1, -1 do
        local line = lines[i]
        local drawn_icon = self:drawHelpLine(x, y, line.text, line.key1, line.key2)
        y = y - delta_y
        valid_icon = valid_icon or drawn_icon
    end

    if valid_icon then
        local line_x = x + 10
        draw.ShadowedLine(line_x, y_start + 2, line_x, y + 8, COLOR_WHITE)
    end
end

function PlayerController:drawHelpLine(x, y, text, key1, key2)
    local valid_icon = true

    if isstring(key1) and key2 == nil then
        self:drawKeyBox(x, y, key1)
    elseif isstring(key1) and isstring(key2) then
        local key2_width = draw.GetTextSize(key2, "weapon_hud_help_key")
        self:drawKeyBox(x-25-key2_width, y, key1)
        draw.ShadowedText("+", "weapon_hud_help", x-8-key2_width, y, COLOR_WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        self:drawKeyBox(x, y, key2)
    else
        valid_icon = false
    end

    draw.ShadowedText(TryT(text), "weapon_hud_help", x + 20, y, COLOR_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)

    return valid_icon
end

function PlayerController:drawKeyBox(x, y, key)
    local pad = 3
    local pad2 = pad * 2

    x = x - pad + 1
    y = y - pad2 * 0.5 + 1

    local key_box_w, key_box_h = draw.GetTextSize(key, "weapon_hud_help_key")

    key_box_w = key_box_w + 3 * pad
    key_box_h = key_box_h + pad2

    local key_box_x = x - key_box_w + 1.5 * pad
    local key_box_y = y - key_box_h + 0.5 * pad2

    surface.SetDrawColor(0, 0, 0, 150)
    surface.DrawRect(key_box_x, key_box_y, key_box_w, key_box_h)
    draw.ShadowedText(key, "weapon_hud_help_key", x, y, COLOR_WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    draw.OutlinedShadowedBox(key_box_x, key_box_y, key_box_w, key_box_h, 1, COLOR_WHITE)
end

-- Disable Pickup Notification for the c_ply
function PlayerController.pickupNotification()
    return false
end
