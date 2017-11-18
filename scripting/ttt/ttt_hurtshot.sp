#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>

#include <ttt_shop>
#include <ttt>
#include <config_loader>
#include <multicolors>

#define SHORT_NAME "hurtshot"

#define PLUGIN_NAME TTT_PLUGIN_NAME ... " - Items: Hurtshot"

int g_iPrice = 0;
int g_iPrio = 0;
int g_iCount = 0;
int g_iDmg = 0;
int g_iGCount[MAXPLAYERS + 1] = { 0, ... };

bool hasHS[MAXPLAYERS + 1] = { false, ... };
ArrayList listHS;

char g_sConfigFile[PLATFORM_MAX_PATH] = "";
char g_sPluginTag[PLATFORM_MAX_PATH] = "";
char g_sLongName[64];

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = TTT_PLUGIN_AUTHOR,
	description = TTT_PLUGIN_DESCRIPTION,
	version = TTT_PLUGIN_VERSION,
	url = TTT_PLUGIN_URL
};

public void OnPluginStart()
{
	TTT_IsGameCSGO();

	LoadTranslations("ttt.phrases");

	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/config.cfg");
	Config_Setup("TTT", g_sConfigFile);

	Config_LoadString("ttt_plugin_tag", "{orchid}[{green}T{darkred}T{blue}T{orchid}]{lightgreen} %T", "The prefix used in all plugin messages (DO NOT DELETE '%T')", g_sPluginTag, sizeof(g_sPluginTag));

	Config_Done();

	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/hurtshot.cfg");

	Config_Setup("TTT-Hurtshot", g_sConfigFile);
	Config_LoadString("hurts_name", "Hurtshot", "The name of the Hurtshot in the Shop", g_sLongName, sizeof(g_sLongName));

	g_iPrice = Config_LoadInt("hurts_traitor_price", 5000, "The amount of credits for hurtshots costs as traitor. 0 to disable.");
	g_iCount = Config_LoadInt("hurts_traitor_count", 1, "The amount of usages for hurtshots per round as traitor. 0 to disable.");
	g_iPrio = Config_LoadInt("hurts_traitor_sort_prio", 0, "The sorting priority of the hurtshots (Traitor) in the shop menu.");
	g_iDmg = Config_LoadInt("hurts_traitor_damage", 50, "The damage of the hurtshot");

	Config_Done();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("weapon_fire", Event_Fire, EventHookMode_Pre);
	
	listHS = new ArrayList();
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, EquipHS);
	SDKHook(client, SDKHook_WeaponDropPost, DropHS);		
}

public void OnClientDisconnect(int client)
{
	ResetHurtshot(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (TTT_IsClientValid(client))
	{
		ResetHurtshot(client);
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	listHS.Clear();
}

public Action Event_Fire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char weapon[64];
	GetEventString(event, "weapon", weapon, sizeof(weapon));
	
	if (TTT_IsClientValid(client) && StrEqual(weapon, "weapon_healthshot"))
	{
		if (hasHS[client] && GetClientHealth(client) < 100)
		{
			DataPack data = new DataPack();
			int calcul = GetClientHealth(client) - (g_iDmg);
			if (calcul <= 0)
				CreateTimer(1.0, ChangeHP, data);		
			else
				CreateTimer(2.0, ChangeHP, data);	
			data.WriteCell(client);
			data.WriteCell(calcul);
			hasHS[client] = false;			
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

Action EquipHS(int client, int weapon)
{
	if (TTT_IsClientValid(client) && listHS.FindValue(weapon) != -1)
	{
		hasHS[client] = true;
	}
	return Plugin_Continue;
}

Action DropHS(int client, int weapon)
{
	if (TTT_IsClientValid(client) && listHS.FindValue(weapon) != -1)
	{
		hasHS[client] = false;	
	}
	return Plugin_Continue;
}

public Action ChangeHP(Handle timer, Handle data)
{
	ResetPack(data);
	int client = ReadPackCell(data);
	int calcul = ReadPackCell(data);
	
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if (calcul <= 0)
		{
			ForcePlayerSuicide(client);
		}
		else
		{
			SetEntityHealth(client, calcul);
		}
	}
	delete data;
	return Plugin_Handled;
}

public void OnAllPluginsLoaded()
{
	TTT_RegisterCustomItem(SHORT_NAME, g_sLongName, g_iPrice, TTT_TEAM_TRAITOR, g_iPrio);
}

public Action TTT_OnItemPurchased(int client, const char[] itemshort, bool count)
{
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if (StrEqual(itemshort, SHORT_NAME, false))
		{
			int role = TTT_GetClientRole(client);

			if (role != TTT_TEAM_TRAITOR)
			{
				return Plugin_Stop;
			}				

			if (role == TTT_TEAM_TRAITOR && g_iGCount[client] >= g_iCount)
			{
				CPrintToChat(client, g_sPluginTag, "Bought All", client, g_sLongName, g_iCount);
				return Plugin_Stop;
			}
			
			int ent = GivePlayerItem(client, "weapon_healthshot");
			listHS.Push(ent);

			if (count)
			{
				g_iGCount[client]++;
			}
		}
	}
	return Plugin_Continue;
}

void ResetHurtshot(int client)
{
	g_iGCount[client] = 0;
	hasHS[client] = false;	
}