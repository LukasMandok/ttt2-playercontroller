PlayerController = PlayerController or {}

print("Load In sh_playercontroller")

-- FLAGGS

-- Server Network Flags
PC_SV_START = 0
PC_SV_END = 1
PC_SV_MESSAGE = 2
PC_SV_INVENTORY = 3
PC_SV_PLAYER = 4

PC_SERVERSIDE = 0
PC_CLIENTSIDE = 1

-- Pickups
PC_PICKUP_WEAPON = 0
PC_PICKUP_ITEM = 1
PC_PICKUP_AMMO = 2

-- Client Network Flags
PC_CL_START = 0
PC_CL_END = 1
PC_CL_SWITCH = 2

PC_CL_WEAPON = 0
PC_CL_DROP_WEAPON = 1
PC_CL_INVENTORY = 2
PC_CL_MESSAGE = 3

-- View_Flags
PC_CAM_ROAMING = 0
PC_CAM_THIRDPERSON = 1
PC_CAM_FIRSTPERSON = 2
PC_CAM_SIMPLEFIRSTPERSON = 3


-- Redirecting c_ply messages to t_ply
PC_SV_NET = {
	["ttt2sprinttoggle"] = true,
	["ttt2_switch_weapon"] = true,
	["ttt2orderequipment"] = true,
}

-- PC_CL_MESSAGES = {
-- 	["TTT_Radar"] = true,
-- 	["TTT2RadarUpdateTime"] = true,
-- 	["TTT2RadarUpdateAutoScan"] = true,
-- }


-- Calculate t_ply moves:
--function PlayerController.calculateMove()

-- Add is controller functino:
local ply_meta = FindMetaTable("Player")

function ply_meta:IsController(ply)
	if ply then
		return self.controller and self.controller.c_ply == self and self.controller.t_ply == ply or false
	else
		return self.controller and self.controller.c_ply == self or false
	end
end

function ply_meta:IsControlled(ply)
	if ply then
		return self.controller and self.controller.t_ply == self and self.controller.c_ply == ply or false
	else
		return self.controller and self.controller.t_ply == self or false
	end
end


-- SERVER

function PlayerController.preventAnimations( ply, event, data )
	if ply:IsController() then
		return ACT_INVALID
	end
end

-- function PlayerController.preventAttacking(ply, mv, cmd)
-- 	if ply:IsController() then
-- 		return true
-- 	end
-- end

-- Disable Movment for the controlling player
function PlayerController.disableMovment(ply, mv)
	if ply:IsController() then
		ply:SetFOV(ply.controller["t_ply"]:GetFOV())
		return true
	end
end

-- Disable Weapon Switch for the controlling Player
function PlayerController.disableWeaponSwitch(ply, oldWep, newWep )
	if ply:IsController() then
		print("Disable Weapon Switch for:", ply:Nick(), "from:", oldWep, "to:", newWep)
		return true
	end
end

-- Prevents Controller from using Flashlight and toggles flashlight of target instead
function PlayerController.controlFlashlight( ply, enabled )
	if ply:IsController()  then
		ply.controller["t_ply"]:Flashlight( not ply.controller["t_ply"]:FlashlightIsOn() )
		return false
	end
end

-- prevent the controller from bying something from the shop
-- relay in net message since this hook is not called when the controlling player does not have the rights to by an item
-- function PlayerController.preventEquipmentOrder(ply, cls, is_item, credits)
--     -- allow, ignoreCost, message = hook.Run("TTT2CanOrderEquipment")
--     if ply.controller and ply.controller["t_ply"] then
--         print("Prevent Controller from bying something:", ply:Nick())
--         return false
--     end
-- end

-- SHARED

function PlayerController:targetMove(cmd)
	local t_ply = self.t_ply
	local c_ply = self.c_ply

	cmd:ClearButtons()
	cmd:ClearMovement()

	-- write commands you want to handle yourself
	-- return true to skip standardhanling of remaining inputs
	-- do:   commands = t_ply (to only take commands of target Player)
	--       commands = c_ply (to only take comands of controlling Player)   
	local commands, flag = hook.Run("PlayerController:OverrideTargetCommands", c_ply, t_ply, commands, self.net_flag)
	
	flag = flag or false 
	commands = commands or {}

	if flag == false then
		-- do some standard input handling
		--print("Do standrad input handling")
		local angles = t_ply:EyeAngles()
		--print("cameraAngles: ", c_ply["CameraAngles"], "angles", angles)

		if self.net_flag == PC_CLIENTSIDE then
			angles.pitch  = math.Clamp((angles).pitch + (t_ply["MouseY"] or 0) * 0.001 + (c_ply["MouseY"] or 0) * 0.001, -85, 85) -- todo: es könnte sein, dass das nicht funktioniert
			angles.yaw    = 		   (angles).yaw   - (t_ply["MouseX"] or 0) * 0.001 - (c_ply["MouseX"] or 0) * 0.001           --       da auf dem Client eine andere Richtung berechnet wird.
		else
			angles.pitch  = math.Clamp((c_ply["CameraAngles"] or angles).pitch + (t_ply["MouseY"] or 0) * 0.01, -85, 85) -- todo: es könnte sein, dass das nicht funktioniert
			angles.yaw    = (c_ply["CameraAngles"] or angles).yaw              - (t_ply["MouseX"] or 0) * 0.01           --       da auf dem Client eine andere Richtung berechnet wird.
		end

		-- if self.net_flag == PC_SERVERSIDE then
		-- 	angles.pitch  = math.Clamp((c_ply["CameraAngles"] or angles).pitch + (t_ply["MouseY"] or 0) * 0.01, -85, 85) -- todo: es könnte sein, dass das nicht funktioniert
		-- 	angles.yaw    = (c_ply["CameraAngles"] or angles).yaw     
		-- else
		-- 	angles = t_ply["CameraAngles"]
		-- end

		commands["CameraAngles"] = commands["CameraAngles"] or angles
		commands["Buttons"]      = commands["Buttons"]      or ((t_ply["Buttons"] or 0)     + (c_ply["Buttons"] or 0))
		commands["Impulse"]      = commands["Impulse"]      or ((t_ply["Impulse"] or 0)     + (c_ply["Impulse"] or 0))
		commands["ForwardMove"]  = commands["ForwardMove"]  or ((t_ply["ForwardMove"] or 0) + (c_ply["ForwardMove"] or 0))
		commands["SideMove"]     = commands["SideMove"]     or ((t_ply["SideMove"] or 0)    + (c_ply["SideMove"] or 0))
		commands["UpMove"]       = commands["UpMove"]       or ((t_ply["UpMove"] or 0)      + (c_ply["UpMove"] or 0))
		commands["MouseWheel"]   = commands["MouseWheel"]   or ((t_ply["MouseWheel"] or 0)  + (c_ply["MouseWheel"] or 0))
		commands["MouseX"]       = commands["MouseX"]       or ((t_ply["MouseX"] or 0)      + (c_ply["MouseX"] or 0))
		commands["MouseY"]       = commands["MouseY"]       or ((t_ply["MouseY"] or 0)      + (c_ply["MouseY"] or 0))
	else
		--print("Skip standard handling")
	end


	-- -- only take t_ply commands
	-- if result != nil and result == false then
	--     commands["CameraAngles"] = c_ply["CameraAngles"] or t_ply:EyeAngles()
	--     commands["Buttons"]      = c_ply["Buttons"]      or 0
	--     commands["Impulse"]      = c_ply["Impulse"]      or 0
	--     commands["ForwardMove"]  = c_ply["ForwardMove"]  or 0
	--     commands["SideMove"]     = c_ply["SideMove"]     or 0
	--     commands["UpMove"]       = c_ply["UpMove"]       or 0
	--     commands["MouseWheel"]   = c_ply["MouseWheel"]   or 0
	--     commands["MouseX"]       = c_ply["MouseX"]       or 0
	--     commands["MouseY"]       = c_ply["MouseY"]       or 0

	-- -- only take c_ply commands
	-- elseif result == true then
	--     commands["CameraAngles"] = c_ply["CameraAngles"] or t_ply:EyeAngles()
	--     commands["Buttons"]      = c_ply["Buttons"]      or 0
	--     commands["Impulse"]      = c_ply["Impulse"]      or 0
	--     commands["ForwardMove"]  = c_ply["ForwardMove"]  or 0
	--     commands["SideMove"]     = c_ply["SideMove"]     or 0
	--     commands["UpMove"]       = c_ply["UpMove"]       or 0
	--     commands["MouseWheel"]   = c_ply["MouseWheel"]   or 0
	--     commands["MouseX"]       = c_ply["MouseX"]       or 0
	--     commands["MouseY"]       = c_ply["MouseY"]       or 0
	-- end 

	--if not IsValid(c_ply) then return end

	-- cmd:SetButtons(c_ply:GetNWInt("PlayerController_Buttons", 0))
	-- cmd:SetImpulse(c_ply:GetNWInt("PlayerController_Impluse", 0))

	--print("commands:", commands["CameraAngles"], "c_ply", c_ply["CameraAngles"])

	-- TODO, das muss bearbeitet werden, um eine Überlagerung von Comands zu ermöglichen
	t_ply:SetEyeAngles(commands["CameraAngles"] or t_ply:EyeAngles())

	cmd:SetButtons(commands["Buttons"] or 0)
	cmd:SetImpulse(commands["Impulse"] or 0)

	cmd:SetForwardMove(commands["ForwardMove"] or 0)
	cmd:SetSideMove(commands["SideMove"] or 0)
	cmd:SetUpMove(commands["UpMove"] or 0)

	cmd:SetMouseWheel(commands["MouseWheel"] or 0)
	--cmd:SetMouseX(commands["MouseX"] or 0)
	--cmd:SetMouseY(commands["MouseY"] or 0)
end



-- Override Shared version of UpdateSprint 

local function PlayerSprint(trySprinting, moveKey)
	if SERVER then return end

	local client = LocalPlayer()

	if trySprinting and not GetGlobalBool("ttt2_sprint_enabled", true) then return end
	if not trySprinting and not client.isSprinting or trySprinting and client.isSprinting then return end
	if client.isSprinting and (client.moveKey and not moveKey or not client.moveKey and moveKey) then return end

	client.oldSprintProgress = client.sprintProgress
	client.sprintMultiplier = trySprinting and (1 + GetGlobalFloat("ttt2_sprint_max", 0)) or nil
	client.isSprinting = trySprinting
	client.moveKey = moveKey

	net.Start("TTT2SprintToggle")
		net.WriteBool(trySprinting)
	net.SendToServer()
end

local function UpdateSprintOverride()
	local client

	if CLIENT then
		client = LocalPlayer()

		if not IsValid(client) then return end
	end

	local plys = client and {client} or player.GetAll()

	for i = 1, #plys do
		local ply = plys[i]

		if not ply:OnGround() then continue end

		local wantsToMove
		if CLIENT and ply:IsControlled() and IsValid(ply.controller["c_ply"]) then
			wantsToMove = ply.controller.c_ply["ForwardMove"] != 0 or ply.controller.c_ply["SideMove"] != 0
			--local c_ply = ply.controller["c_ply"]
			-- wantsToMove = c_ply:KeyDown(IN_FORWARD)   or c_ply:KeyDown(IN_BACK) or
			-- 			  c_ply:KeyDown(IN_MOVERIGHT) or c_ply:KeyDown(IN_MOVELEFT)
		else
			wantsToMove = ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_BACK) or ply:KeyDown(IN_MOVERIGHT) or ply:KeyDown(IN_MOVELEFT)
		end

		if ply.sprintProgress == 1 and (not ply.isSprinting or not wantsToMove) then continue end
		if ply.sprintProgress == 0 and ply.isSprinting and wantsToMove then
			ply.sprintResetDelayCounter = ply.sprintResetDelayCounter + FrameTime()
			-- If the player keeps sprinting even though they have no stamina, start refreshing stamina after 1.5 seconds automatically
			if CLIENT and ply.sprintResetDelayCounter > 1.5 then
				PlayerSprint(false, ply.moveKey)
			end

			continue
		end

		ply.sprintResetDelayCounter = 0

		local modifier = {1} -- Multiple hooking support

		if not ply.isSprinting or not wantsToMove then
			---
			-- @realm shared
			hook.Run("TTT2StaminaRegen", ply, modifier)

			ply.sprintProgress = math.min((ply.oldSprintProgress or 0) + FrameTime() * modifier[1] * GetGlobalFloat("ttt2_sprint_stamina_regeneration"), 1)
			ply.oldSprintProgress = ply.sprintProgress
		elseif wantsToMove then
			---
			-- @realm shared
			hook.Run("TTT2StaminaDrain", ply, modifier)

			ply.sprintProgress = math.max((ply.oldSprintProgress or 0) - FrameTime() * modifier[1] * GetGlobalFloat("ttt2_sprint_stamina_consumption"), 0)

			ply.oldSprintProgress = ply.sprintProgress
		end
	end
end

-- TODO: WIrd nicht benötigt (glaube ich)
-- function PlayerController.overrideUpdateSprint(flag)
--     if flag == true then
--         UpdateSprint = UpdateSprintOverride
--     else
--         UpdateSprint = OldUpdateSprint
--     end    
-- end

function GM:Think()
	--if PlayerController.isActive then
		--print("overridden sprint")
		UpdateSprintOverride()
		if CLIENT then
			EPOP:Think()
		end
	-- else
	-- 	UpdateSprint()
	-- 	if CLIENT then
	-- 		EPOP:Think()
	-- 	end
	-- end
end

-- relay shop order from 
-- only works if the controller itself is allowed to buy this item



-- NETWORK VARIABLES


-- hook.Add("Move", "PlayerController:DisableControllerMovment", function(ply, mv)

-- end)

-- hook.Add("InputMouseApply", "PlayerControllerler:DisableControllerMouse", PlayerController.disableMouse)


