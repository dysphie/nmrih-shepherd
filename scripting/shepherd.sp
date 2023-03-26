#include <sourcemod>
#include <sdktools>
#include <debugoverlays>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <namecolors>
#define REQUIRE_PLUGIN

int offs_m_hTouchingEntities = -1;
int g_LaserIndex;
int g_HaloIndex;

ConVar cvHighlightTrigger;

public Plugin myinfo =
{
	name = "Shepherd",
	author = "Dysphie",
	description = "Displays the names of players who are absent from areas that require all players to be present",
	version = "1.0.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("GetColoredName");
    return APLRes_Success;
}

public void OnPluginStart()
{
	cvHighlightTrigger = CreateConVar("sv_shepherd_highlight_trigger", "1", 
		"Whether to display all-player triggers to the player who issued the command");
		
	LoadTranslations("shepherd.phrases");
	GameData gamedata = new GameData("shepherd.games");
	offs_m_hTouchingEntities = GetOffsetOrFail(gamedata, "CBaseTrigger::m_hTouchingEntities");

	RegConsoleCmd("sm_missing", Cmd_Missing, "Displays the names of players who are absent from areas that require the whole team");
	RegAdminCmd("sm_missingall", Cmd_MissingAll, ADMFLAG_BAN);
	RegConsoleCmd("sm_quienfalta", Cmd_Missing, "Muestra los nombres de jugadores que están ausentes de áreas que requieren a todo el equipo");
}


public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (client && StrEqual(sArgs, "quien falta", false))
	{
		ClientCommand(client, "sm_missing");
	}

	return Plugin_Continue;
}

Action Cmd_MissingAll(int client, int args)
{
	// Poll all trigger_allplayer to see if they contain our player

	int trigger = -1;

	ArrayList missingTeammates = new ArrayList();
	int numTouchingTriggers = 0;

	// float clientPos[3];
	// GetClientAbsOrigin(client, clientPos);

	while ((trigger = FindEntityByClassname(trigger, "trigger_allplayer")) != -1)
	{
		Address m_hTouchingEntities = GetEntityAddress(trigger) + view_as<Address>(offs_m_hTouchingEntities); // CUtlVector<CHandle<CBaseEntity>,CUtlMemory<CHandle<CBaseEntity>,int>>

		if (!m_hTouchingEntities) {
			continue;
		}

		int maxEnts = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0xC), NumberType_Int32); // CUtlVector::m_nSize
		Address elements = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0x10), NumberType_Int32); // UtlVector::m_pElements

		ArrayList touchingEnts = new ArrayList();

		// Get all the clients touching this trigger
		for (int i = 0; i < maxEnts; i++)
		{
			int touching = LoadEntityFromHandleAddress(elements + view_as<Address>(i * 0x4)); // The first thingy being stored
			if (0 < touching <= MaxClients) {
				touchingEnts.Push(touching);
			}
		}

		// Our client is not in this trigger, we don't care
		if (touchingEnts.FindValue(client) == -1) 
		{
			delete touchingEnts;
			continue;
		}
		
		numTouchingTriggers++;

		for (int teammate = 1; teammate <= MaxClients; teammate++)
		{
			if (teammate == client || !IsClientInGame(teammate) || !IsPlayerAlive(teammate)) 
			{
				// TODO: Check CBaseTrigger::PassesTriggerFilters(teammate)
				continue;
			}

			if (touchingEnts.FindValue(teammate) == -1 && missingTeammates.FindValue(teammate) == -1) 
			{
				missingTeammates.Push(teammate);
			}
		}

		if (cvHighlightTrigger.BoolValue) {
			HighlightTrigger(client, trigger);
		}

		delete touchingEnts;
	}

	if (!numTouchingTriggers) 
	{
		delete missingTeammates;
		
		PrintToServer("Not Inside Trigger");
		CPrintToChatAll("%t", "Not Inside Trigger");
		return Plugin_Handled;
	}

	char humanList[255];
	char teammateName[MAX_NAME_LENGTH];

	int maxMissingTeammates = missingTeammates.Length;
	for (int i = 0; i < maxMissingTeammates; i++)
	{
		int teammate = missingTeammates.Get(i);
		GetBestPlayerName(teammate, teammateName, sizeof(teammateName));
		if (i == 0) {
			Format(humanList, sizeof(humanList), "%s", teammateName);
		}
		else {
			Format(humanList, sizeof(humanList), "%s, %s", humanList, teammateName);
		}
	}

	delete missingTeammates;
	
	PrintToServer("end");
	CPrintToChatAll("%t", "Absent Players", maxMissingTeammates, humanList);
	return Plugin_Handled;
}

Action Cmd_Missing(int client, int args)
{
	// Poll all trigger_allplayer to see if they contain our player

	int trigger = -1;

	ArrayList missingTeammates = new ArrayList();
	int numTouchingTriggers = 0;

	// float clientPos[3];
	// GetClientAbsOrigin(client, clientPos);

	while ((trigger = FindEntityByClassname(trigger, "trigger_allplayer")) != -1)
	{
		Address m_hTouchingEntities = GetEntityAddress(trigger) + view_as<Address>(offs_m_hTouchingEntities); // CUtlVector<CHandle<CBaseEntity>,CUtlMemory<CHandle<CBaseEntity>,int>>

		if (!m_hTouchingEntities) {
			continue;
		}

		int maxEnts = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0xC), NumberType_Int32); // CUtlVector::m_nSize
		Address elements = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0x10), NumberType_Int32); // UtlVector::m_pElements

		ArrayList touchingEnts = new ArrayList();

		// Get all the clients touching this trigger
		for (int i = 0; i < maxEnts; i++)
		{
			int touching = LoadEntityFromHandleAddress(elements + view_as<Address>(i * 0x4)); // The first thingy being stored
			if (0 < touching <= MaxClients) {
				touchingEnts.Push(touching);
			}
		}

		// Our client is not in this trigger, we don't care
		if (touchingEnts.FindValue(client) == -1) 
		{
			delete touchingEnts;
			continue;
		}
		
		numTouchingTriggers++;

		for (int teammate = 1; teammate <= MaxClients; teammate++)
		{
			if (teammate == client || !IsClientInGame(teammate) || !IsPlayerAlive(teammate)) 
			{
				// TODO: Check CBaseTrigger::PassesTriggerFilters(teammate)
				continue;
			}

			if (touchingEnts.FindValue(teammate) == -1 && missingTeammates.FindValue(teammate) == -1) 
			{
				missingTeammates.Push(teammate);
			}
		}

		if (cvHighlightTrigger.BoolValue) {
			HighlightTrigger(client, trigger);
		}

		delete touchingEnts;
	}

	if (!numTouchingTriggers) 
	{
		delete missingTeammates;
		
		PrintToServer("Not Inside Trigger");
		CPrintToChat(client, "%t", "Not Inside Trigger");
		return Plugin_Handled;
	}

	char humanList[255];
	char teammateName[MAX_NAME_LENGTH];

	int maxMissingTeammates = missingTeammates.Length;
	for (int i = 0; i < maxMissingTeammates; i++)
	{
		int teammate = missingTeammates.Get(i);
		GetBestPlayerName(teammate, teammateName, sizeof(teammateName));
		if (i == 0) {
			Format(humanList, sizeof(humanList), "%s", teammateName);
		}
		else {
			Format(humanList, sizeof(humanList), "%s, %s", humanList, teammateName);
		}
	}

	delete missingTeammates;
	
	PrintToServer("end");
	CPrintToChat(client, "%t", "Absent Players", maxMissingTeammates, humanList);
	return Plugin_Handled;
}

void GetBestPlayerName(int client, char[] buffer, int maxlen)
{
	if (IsFakeClient(client)) 
	{
		strcopy(buffer, maxlen, "BOT");
		return;
	} 

	if (GetFeatureStatus(FeatureType_Native, "GetColoredName") == FeatureStatus_Available) {
		GetColoredName(client, buffer, maxlen);
	} else {
		GetClientName(client, buffer, maxlen);
	}
}

int GetOffsetOrFail(GameData gamedata, const char[] key)
{
	int offset = gamedata.GetOffset(key);
	if (offset == -1)
	{
		SetFailState("Failed to find offset \"%s\"", key);
	}
	return offset;
}

// Taken from Silvers' Dev Cmds
// https://forums.alliedmods.net/showthread.php?p=1729015
void HighlightTrigger(int client, int entity)
{
	float mins[3];
	float maxs[3];
	float pos[3];

	GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Data, "m_vecMaxs", maxs);

	if (mins[0] == maxs[0] && mins[1] == maxs[1] && mins[2] == maxs[2]) {
		return;
	}

	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	AddVectors(pos, maxs, maxs);
	AddVectors(pos, mins, mins);

	float pos1[3], pos2[3], pos3[3], pos4[3], pos5[3], pos6[3];
	pos1 = maxs;
	pos1[0] = mins[0];
	pos2 = maxs;
	pos2[1] = mins[1];
	pos3 = maxs;
	pos3[2] = mins[2];
	pos4 = mins;
	pos4[0] = maxs[0];
	pos5 = mins;
	pos5[1] = maxs[1];
	pos6 = mins;
	pos6[2] = maxs[2];

	TE_SendBeam(client, maxs, pos1);
	TE_SendBeam(client, maxs, pos2);
	TE_SendBeam(client, maxs, pos3);
	TE_SendBeam(client, pos6, pos1);
	TE_SendBeam(client, pos6, pos2);
	TE_SendBeam(client, pos6, mins);
	TE_SendBeam(client, pos4, mins);
	TE_SendBeam(client, pos5, mins);
	TE_SendBeam(client, pos5, pos1);
	TE_SendBeam(client, pos5, pos3);
	TE_SendBeam(client, pos4, pos3);
	TE_SendBeam(client, pos4, pos2);
}

void TE_SendBeam(int client, const float mins[3], const float maxs[3])
{
	TE_SetupBeamPoints(mins, maxs, g_LaserIndex, g_HaloIndex, 0, 0, 5.0, 1.0, 1.0, 1, 0.0, { 255, 0, 0, 255 }, 0);
	TE_SendToClient(client);
}

public void OnMapStart()
{
	g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloIndex = PrecacheModel("materials/sprites/halo01.vmt");
}