#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>

#define PL_VERSION "1.0"
#define MAXENTITIES 2048

public Plugin:myinfo =
{
	name = "[All] Prop Health",
	author = "Roy (Christian Deacon)",
	description = "Props now have health!",
	version = PL_VERSION,
	url = "GFLClan.com && TheDevelopingCommunity.com"
};

// ConVars
new Handle:g_hConfigPath = INVALID_HANDLE;
new Handle:g_hDefaultHealth = INVALID_HANDLE;
new Handle:g_hDefaultMultiplier = INVALID_HANDLE;
new Handle:g_hColor = INVALID_HANDLE;
new Handle:g_hTeamRestriction = INVALID_HANDLE;
new Handle:g_hDebug = INVALID_HANDLE;

// ConVar Values
new String:g_sConfigPath[PLATFORM_MAX_PATH];
new g_iDefaultHealth;
new Float:g_fDefaultMultiplier;
new String:g_sColor[32];
new g_iTeamRestriction;
new bool:g_bDebug;

// Other Variables
new g_arrPropHealth[MAXENTITIES + 1];
new String:g_sLogFile[PLATFORM_MAX_PATH];

public OnPluginStart()
{
	// ConVars
	CreateConVar("sm_ph_version", PL_VERSION, "Prop Health's version.");
	
	g_hConfigPath = CreateConVar("sm_ph_config_path", "configs/prophealth.props.cfg", "The path to the Prop Health config.");
	HookConVarChange(g_hConfigPath, CVarChanged);
	
	g_hDefaultHealth = CreateConVar("sm_ph_default_health", "-1", "A prop's default health if not defined in the config file. -1 = Doesn't break.");
	HookConVarChange(g_hDefaultHealth, CVarChanged);	
	
	g_hDefaultMultiplier = CreateConVar("sm_ph_default_multiplier", "325.00", "Default multiplier based on the player count (for zombies/humans). Default: 65 * 5 (65 damage by right-click knife with 5 hits)");
	HookConVarChange(g_hDefaultMultiplier, CVarChanged);	
	
	g_hColor = CreateConVar("sm_ph_color", "255 0 0 255", "If a prop has a color, set it to this color. -1 = no color. uses RGBA.");
	HookConVarChange(g_hColor, CVarChanged);	
	
	g_hTeamRestriction = CreateConVar("sm_ph_team", "2", "What team are allowed to destroy props? 0 = no restriction, 1 = humans, 2 = zombies.");
	HookConVarChange(g_hTeamRestriction, CVarChanged);	
	
	g_hDebug = CreateConVar("sm_ph_debug", "0", "Enable debugging (logging will go to logs/prophealth-debug.log).");
	HookConVarChange(g_hDebug, CVarChanged);
	
	AutoExecConfig(true, "plugin.prop-health");
	
	// Commands
	RegConsoleCmd("sm_getpropinfo", Command_GetPropInfo);
}

public CVarChanged(Handle:hCVar, const String:sOldV[], const String:sNewV[])
{
	OnConfigsExecuted();
}

public OnConfigsExecuted()
{
	GetConVarString(g_hConfigPath, g_sConfigPath, sizeof(g_sConfigPath));
	g_iDefaultHealth = GetConVarInt(g_hDefaultHealth);
	g_fDefaultMultiplier = GetConVarFloat(g_hDefaultMultiplier);
	GetConVarString(g_hColor, g_sColor, sizeof(g_sColor));
	g_iTeamRestriction = GetConVarInt(g_hTeamRestriction);
	g_bDebug = GetConVarBool(g_hDebug);
	
	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/prophealth-debug.log");
}

public OnMapStart()
{
	PrecacheSound("physics/metal/metal_box_break1.wav");
	PrecacheSound("physics/metal/metal_box_break2.wav");
}

public OnEntityCreated(iEnt, const String:sClassname[])
{
	SDKHook(iEnt, SDKHook_SpawnPost, OnEntitySpawned);
}

public OnEntitySpawned(iEnt)
{
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		g_arrPropHealth[iEnt] = -1;
		SetPropHealth(iEnt);
	}
}

public Action:Hook_OnTakeDamage(iEnt, &iAttacker, &iInflictor, &Float:fDamage, &iDamageType)
{
	if (!iAttacker || !IsClientInGame(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not valid.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (!IsValidEntity(iEnt) || !IsValidEdict(iEnt))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Prop not valid.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (g_arrPropHealth[iEnt] < 0)
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Prop health under 0.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	if (g_iTeamRestriction == 1 && ZR_IsClientZombie(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not on the right team.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}	
	
	if (g_iTeamRestriction == 2 && ZR_IsClientHuman(iAttacker))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop %i returned. Attacker (%i) not on the right team.", iEnt, iAttacker);
		}
		
		return Plugin_Continue;
	}
	
	g_arrPropHealth[iEnt] -= RoundToZero(fDamage);
	
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop Damaged (Prop: %i) (Damage: %f) (Health: %i)", iEnt, fDamage, g_arrPropHealth[iEnt]);
	}
	
	if (g_arrPropHealth[iEnt] < 1)
	{
		// Destroy the prop.
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop Destroyed (Prop: %i)", iEnt);
		}
		
		AcceptEntityInput(iEnt, "kill");
		RemoveEdict(iEnt);
		
		g_arrPropHealth[iEnt] = -1;
	}
	
	// Play a sound.
	new iRand = GetRandomInt(1, 2);
	switch (iRand)
	{
		case 1:
		{
			new Float:fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break1.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
		case 2:
		{
			new Float:fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break2.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
	}
	
	return Plugin_Continue;
}

public Action:Command_GetPropInfo(iClient, iArgs)
{
	new iEnt = GetClientAimTarget(iClient, false);
	
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		decl String:sModelName[PLATFORM_MAX_PATH];
		GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
		PrintToChat(iClient, "\x03[PH]\x02(Model: %s) (Prop Health: %i) (Prop Index: %i)", sModelName, g_arrPropHealth[iEnt], iEnt);
	}
	else
	{
		PrintToChat(iClient, "\x03[PH]\x02Prop is either a player or invalid. (Prop Index: %i)", iEnt);
	}
	
	return Plugin_Handled;
}

stock SetPropHealth(iEnt)
{
	decl String:sClassname[MAX_NAME_LENGTH];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname));
	
	if (!StrEqual(sClassname, "prop_physics", false) && !StrEqual(sClassname, "prop_physics_override", false) && !StrEqual(sClassname, "prop_physics_multiplayer", false))
	{
		return;
	}

	decl String:sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), g_sConfigPath);
	
	new Handle:hKV = CreateKeyValues("Props");
	FileToKeyValues(hKV, sFile);
	
	decl String:sPropModel[PLATFORM_MAX_PATH];
	GetEntPropString(iEnt, Prop_Data, "m_ModelName", sPropModel, sizeof(sPropModel));
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop model found! (Prop: %i) (Prop Model: %s)", iEnt, sPropModel);
	}
	
	if (KvGotoFirstSubKey(hKV))
	{
		decl String:sBuffer[PLATFORM_MAX_PATH];
		do
		{
			KvGetSectionName(hKV, sBuffer, sizeof(sBuffer));
			if (g_bDebug)
			{
				LogToFile(g_sLogFile, "Checking prop model. (Prop: %i) (Prop Model: %s) (Section Model: %s)", iEnt, sPropModel, sBuffer);
			}
			
			if (StrEqual(sBuffer, sPropModel, false))
			{
				if (g_bDebug)
				{
					LogToFile(g_sLogFile, "Prop model matches. (Prop: %i) (Prop Model: %s)", iEnt, sPropModel);
				}
				
				g_arrPropHealth[iEnt] = KvGetNum(hKV, "health");
				
				new Float: fMultiplier = KvGetFloat(hKV, "multiplier");
				new iClientCount = GetRealClientCount();
				new Float:fAddHealth = float(iClientCount) * fMultiplier;
				
				g_arrPropHealth[iEnt] += RoundToZero(fAddHealth);
				
				if (g_bDebug)
				{
					LogToFile(g_sLogFile, "Custom prop's health set. (Prop: %i) (Prop Health: %i) (Multiplier: %f) (Added Health: %i) (Client Count: %i)", iEnt, g_arrPropHealth[iEnt], fMultiplier, RoundToZero(fAddHealth), iClientCount);
				}
			}
		} while (KvGotoNextKey(hKV));
	}
	
	if (hKV != INVALID_HANDLE)
	{
		CloseHandle(hKV);
	}
	else
	{			
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "hKV was never valid.");
		}
	}
	
	if (g_arrPropHealth[iEnt] < 1)
	{
		g_arrPropHealth[iEnt] = g_iDefaultHealth;
		
		new iClientCount = GetRealClientCount();
		new Float:fAddHealth = float(iClientCount) * g_fDefaultMultiplier;
		
		g_arrPropHealth[iEnt] += RoundToZero(fAddHealth);
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being set to default health. (Prop: %i) (O - Default Health: %i) (Default Multiplier: %f) (Added Health: %i) (Health: %i) (Client Count: %i)", iEnt, g_iDefaultHealth, g_fDefaultMultiplier, RoundToZero(fAddHealth), g_arrPropHealth[iEnt], iClientCount);
		}
	}
	else
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop already has a health value! (Prop: %i) (Health: %i)", iEnt, g_arrPropHealth[iEnt]);
		}
	}
	
	if (g_arrPropHealth[iEnt] > 0 && !StrEqual(g_sColor, "-1", false))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being colored! (Prop: %i)", iEnt);
		}
		
		// Set the entities color.
		decl String:sBit[4][32];
		
		ExplodeString(g_sColor, " ", sBit, sizeof (sBit), sizeof (sBit[]));
		SetEntityRenderColor(iEnt, StringToInt(sBit[0]), StringToInt(sBit[1]), StringToInt(sBit[2]), StringToInt(sBit[3]));
	}
	
	if (g_arrPropHealth[iEnt] > 0)
	{
		SDKHook(iEnt, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

stock GetRealClientCount()
{
	new iCount;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) != 1)
		{
			iCount++;
		}
	}
	
	return iCount;
}