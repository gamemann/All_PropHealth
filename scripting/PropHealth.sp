#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombiereloaded>
#include <multicolors>

#pragma newdecls required

#define PL_VERSION "1.1"
#define MAXENTITIES 2048

public Plugin myinfo =
{
	name = "[All] Prop Health",
	author = "Roy (Christian Deacon) (minor fixes by N1ckles)",
	description = "Props now have health!",
	version = PL_VERSION,
	url = "GFLClan.com && TheDevelopingCommunity.com"
};

enum Props
{
	iHealth,
	Float:fMultiplier
};

// ConVars
ConVar g_hConfigPath = null;
ConVar g_hDefaultHealth = null;
ConVar g_hDefaultMultiplier = null;
ConVar g_hColor = null;
ConVar g_hTeamRestriction = null;
ConVar g_hPrint = null;
ConVar g_hPrintType = null;
ConVar g_hPrintMessage = null;
ConVar g_hDebug = null;

// ConVar Values
char g_sConfigPath[PLATFORM_MAX_PATH];
int g_iDefaultHealth;
float g_fDefaultMultiplier;
char g_sColor[32];
int g_iTeamRestriction;
bool g_bPrint;
int g_iPrintType;
char g_sPrintMessage[256];
bool g_bDebug;

// Other Variables
int g_arrProp[MAXENTITIES + 1][Props];
char g_sLogFile[PLATFORM_MAX_PATH];

public void OnPluginStart()
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
	
	g_hPrint = CreateConVar("sm_ph_print", "1", "Print the prop's health when damaged to the attacker's chat?");
	HookConVarChange(g_hPrint, CVarChanged);		
	
	g_hPrintType = CreateConVar("sm_ph_print_type", "1", "The print type (if \"sm_ph_print\" is set to 1). 1 = PrintToChat, 2 = PrintCenterText, 3 = PrintHintText.");
	HookConVarChange(g_hPrintType, CVarChanged);		
	
	g_hPrintMessage = CreateConVar("sm_ph_print_message", "{darkred}[PH]{default}Prop Health: {lightgreen}%i", "The message to send to the client. Multicolors supported only for PrintToChat. %i = health value.");
	HookConVarChange(g_hPrintMessage, CVarChanged);	
	
	g_hDebug = CreateConVar("sm_ph_debug", "0", "Enable debugging (logging will go to logs/prophealth-debug.log).");
	HookConVarChange(g_hDebug, CVarChanged);
	
	AutoExecConfig(true, "plugin.prop-health");
	
	// Commands
	RegConsoleCmd("sm_getpropinfo", Command_GetPropInfo);
}

public void CVarChanged(ConVar hCVar, const char[] sOldV, char[] sNewV)
{
	OnConfigsExecuted();
}

public void OnConfigsExecuted()
{
	GetConVarString(g_hConfigPath, g_sConfigPath, sizeof(g_sConfigPath));
	g_iDefaultHealth = GetConVarInt(g_hDefaultHealth);
	g_fDefaultMultiplier = GetConVarFloat(g_hDefaultMultiplier);
	GetConVarString(g_hColor, g_sColor, sizeof(g_sColor));
	g_iTeamRestriction = GetConVarInt(g_hTeamRestriction);
	g_bPrint = GetConVarBool(g_hPrint);
	g_iPrintType = GetConVarInt(g_hPrintType);
	GetConVarString(g_hPrintMessage, g_sPrintMessage, sizeof(g_sPrintMessage));
	g_bDebug = GetConVarBool(g_hDebug);
	
	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/prophealth-debug.log");
}

public void OnMapStart()
{
	PrecacheSound("physics/metal/metal_box_break1.wav");
	PrecacheSound("physics/metal/metal_box_break2.wav");
}

public void OnEntityCreated(int iEnt, const char[] sClassname)
{
	SDKHook(iEnt, SDKHook_SpawnPost, OnEntitySpawned);
}

public void OnEntitySpawned(int iEnt)
{
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		g_arrProp[iEnt][iHealth] = -1;
		g_arrProp[iEnt][fMultiplier] = 0.0;
		SetPropHealth(iEnt);
	}
}

public Action Hook_OnTakeDamage(int iEnt, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
	if (!iAttacker || iAttacker > MaxClients || !IsClientInGame(iAttacker))
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
	
	if (g_arrProp[iEnt][iHealth] < 0)
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
	
	g_arrProp[iEnt][iHealth] -= RoundToZero(fDamage);
	
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop Damaged (Prop: %i) (Damage: %f) (Health: %i)", iEnt, fDamage, g_arrProp[iEnt][iHealth]);
	}
	
	if (g_arrProp[iEnt][iHealth] < 1)
	{
		// Destroy the prop.
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop Destroyed (Prop: %i)", iEnt);
		}
		
		AcceptEntityInput(iEnt, "kill");
		RemoveEdict(iEnt);
		
		g_arrProp[iEnt][iHealth] = -1;
	}
	
	// Play a sound.
	int iRand = GetRandomInt(1, 2);
	switch (iRand)
	{
		case 1:
		{
			float fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break1.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
		case 2:
		{
			float fPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
			EmitSoundToAll("physics/metal/metal_box_break2.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		}
	}
	
	// Print To Client
	if (g_bPrint && g_arrProp[iEnt][iHealth] > 0)
	{
		if (g_iPrintType == 1)
		{
			// Print To Chat.
			CPrintToChat(iAttacker, g_sPrintMessage, g_arrProp[iEnt][iHealth]);
		}
		else if (g_iPrintType == 2)
		{
			// Print Center Text.
			PrintCenterText(iAttacker, g_sPrintMessage, g_arrProp[iEnt][iHealth]);
		}
		else if (g_iPrintType == 3)
		{
			// Print Hint Text.
			PrintHintText(iAttacker, g_sPrintMessage, g_arrProp[iEnt][iHealth]);
		}
	}
	
	return Plugin_Continue;
}

public Action Command_GetPropInfo(int iClient, int iArgs)
{
	int iEnt = GetClientAimTarget(iClient, false);
	
	if (iEnt > MaxClients && IsValidEntity(iEnt))
	{
		char sModelName[PLATFORM_MAX_PATH];
		GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
		PrintToChat(iClient, "\x03[PH]\x02(Model: %s) (Prop Health: %i) (Prop Index: %i)", sModelName, g_arrProp[iEnt][iHealth], iEnt);
	}
	else
	{
		PrintToChat(iClient, "\x03[PH]\x02Prop is either a player or invalid. (Prop Index: %i)", iEnt);
	}
	
	return Plugin_Handled;
}

stock void SetPropHealth(int iEnt)
{
	char sClassname[MAX_NAME_LENGTH];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname));
	
	if (!StrEqual(sClassname, "prop_physics", false) && !StrEqual(sClassname, "prop_physics_override", false) && !StrEqual(sClassname, "prop_physics_multiplayer", false))
	{
		return;
	}

	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), g_sConfigPath);
	
	KeyValues hKV = CreateKeyValues("Props");
	hKV.ImportFromFile(sFile);
	
	char sPropModel[PLATFORM_MAX_PATH];
	GetEntPropString(iEnt, Prop_Data, "m_ModelName", sPropModel, sizeof(sPropModel));
	if (g_bDebug)
	{
		LogToFile(g_sLogFile, "Prop model found! (Prop: %i) (Prop Model: %s)", iEnt, sPropModel);
	}
	
	if (hKV.GotoFirstSubKey())
	{
		char sBuffer[PLATFORM_MAX_PATH];
		do
		{
			hKV.GetSectionName(sBuffer, sizeof(sBuffer));
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
				
				g_arrProp[iEnt][iHealth] = hKV.GetNum("health");
				
				float fMultiplier2 = hKV.GetFloat("multiplier");
				int iClientCount = GetRealClientCount();
				float fAddHealth = view_as<float>(iClientCount) * fMultiplier2;
				
				g_arrProp[iEnt][iHealth] += RoundToZero(fAddHealth);
				g_arrProp[iEnt][fMultiplier] = fMultiplier2;
				
				if (g_bDebug)
				{
					LogToFile(g_sLogFile, "Custom prop's health set. (Prop: %i) (Prop Health: %i) (Multiplier: %f) (Added Health: %i) (Client Count: %i)", iEnt, g_arrProp[iEnt][iHealth], fMultiplier2, RoundToZero(fAddHealth), iClientCount);
				}
			}
		} while (hKV.GotoNextKey());
	}
	
	if (hKV != null)
	{
		delete hKV;
	}
	else
	{			
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "hKV was never valid.");
		}
	}
	
	if (g_arrProp[iEnt][iHealth] < 1)
	{
		g_arrProp[iEnt][iHealth] = g_iDefaultHealth;
		g_arrProp[iEnt][fMultiplier] = g_fDefaultMultiplier;
		
		int iClientCount = GetRealClientCount();
		float fAddHealth = float(iClientCount) * g_fDefaultMultiplier;
		
		g_arrProp[iEnt][iHealth] += RoundToZero(fAddHealth);
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being set to default health. (Prop: %i) (O - Default Health: %i) (Default Multiplier: %f) (Added Health: %i) (Health: %i) (Client Count: %i)", iEnt, g_iDefaultHealth, g_fDefaultMultiplier, RoundToZero(fAddHealth), g_arrProp[iEnt][iHealth], iClientCount);
		}
	}
	else
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop already has a health value! (Prop: %i) (Health: %i)", iEnt, g_arrProp[iEnt][iHealth]);
		}
	}
	
	if (g_arrProp[iEnt][iHealth] > 0 && !StrEqual(g_sColor, "-1", false))
	{
		if (g_bDebug)
		{
			LogToFile(g_sLogFile, "Prop is being colored! (Prop: %i)", iEnt);
		}
		
		// Set the entities color.
		char sBit[4][32];
		
		ExplodeString(g_sColor, " ", sBit, sizeof (sBit), sizeof (sBit[]));
		SetEntityRenderColor(iEnt, StringToInt(sBit[0]), StringToInt(sBit[1]), StringToInt(sBit[2]), StringToInt(sBit[3]));
	}
	
	if (g_arrProp[iEnt][iHealth] > 0)
	{
		SDKHook(iEnt, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

stock int GetRealClientCount()
{
	int iCount;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) != 1)
		{
			iCount++;
		}
	}
	
	return iCount;
}