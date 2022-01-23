#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>

#pragma newdecls required

bool db_createTableSuccess = false;

char db_createMapTable[] = "CREATE TABLE IF NOT EXISTS `umc_map_weight` ( \
	`MapName` VARCHAR(256) NOT NULL, \
	`GroupName` VARCHAR(256) NOT NULL, \
	`Weight` INT NOT NULL, \
	PRIMARY KEY (`MapName`, `GroupName`) \
);";
char db_createGroupTable[] = "CREATE TABLE IF NOT EXISTS `umc_group_weight` ( \
	`GroupName` VARCHAR(256) NOT NULL, \
	`Weight` INT NOT NULL, \
	PRIMARY KEY (`GroupName`) \
);";

char db_mapInsert[] = "INSERT IGNORE INTO `umc_map_weight` (`MapName`, `GroupName`, `Weight`) VALUES ('%s', '%s', 0);";
char db_mapSelect[] = "SELECT `Weight` FROM `umc_map_weight` WHERE `MapName` = '%s' and `GroupName` = '%s';";
char db_mapUpdate[] = "UPDATE `umc_map_weight` SET `weight` = %d WHERE `MapName` = '%s' and `GroupName` = '%s'";
char db_groupInsert[] = "INSERT IGNORE INTO `umc_group_weight` (`GroupName`, `Weight`) VALUES ('%s', 0);";
char db_groupSelect[] = "SELECT `Weight` FROM `umc_group_weight` WHERE `GroupName` = '%s';";
char db_groupUpdate[] = "UPDATE `umc_group_weight` SET `weight` = %d WHERE `GroupName` = '%s';";

ConVar g_cvarPointAddition = null;
ConVar g_cvarPointMultiplier = null;
ConVar g_cvarPointExponent = null;
int g_iPointAdditionAmount = 1;
float g_fPointMultiplierAmount = 1.0;
float g_fPointExponentAmount = 2.0;

public Plugin myinfo =
{
	name = "[UMC Custom] Weight by election",
	author = "Yuumi-Peusah, Foolish, Jobggun",
	description = "For Foolish server",
	version = "1.0",
	url = ""
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	g_cvarPointAddition = CreateConVar("umc_weight_point_addition", "1", "", _, true, 1.0);
	g_cvarPointMultiplier = CreateConVar("umc_weight_point_multiplier", "1.0", "", _, true, 0.0);
	g_cvarPointExponent = CreateConVar("umc_weight_point_exponent", "1.0", "", _, true, 1.0);

	g_cvarPointAddition.AddChangeHook(CVC_PointAddition);
	g_cvarPointMultiplier.AddChangeHook(CVC_PointMultiplier);
	g_cvarPointExponent.AddChangeHook(CVC_PointExponent);
}

public int UMC_OnReweightMap(Handle kv, const char[] map, const char[] group)
{
	Database db = connectToDatabase();
	if(db == null)
	{
		return 0;
	}

	int point = 0;

	int escapedMapLength = strlen(map) * 2 + 1;
	char[] escapedMap = new char[escapedMapLength];
	db.Escape(map, escapedMap, escapedMapLength);

	int escapedGroupLength = strlen(group) * 2 + 1;
	char[] escapedGroup = new char[escapedGroupLength];
	db.Escape(group, escapedGroup, escapedGroupLength);

	if(!InsertMapWeight(db, escapedMap, escapedGroup)) return 0;

	if(!SelectMapWeight(db, escapedMap, escapedGroup, point)) return 0;
	
	UMC_AddWeightModifier(1.0 + Pow(point * g_fPointMultiplierAmount, g_fPointExponentAmount));
	point += g_iPointAdditionAmount;
	
	if(!UpdateMapWeight(db, escapedMap, escapedGroup, point)) return 0;

	delete db;

	return 0;
}

public int UMC_OnReweightGroup(Handle kv, const char[] group)
{
	Database db = connectToDatabase();
	if(db == null)
	{
		return 0;
	}

	int point = 0;

	int escapedGroupLength = strlen(group) * 2 + 1;
	char[] escapedGroup = new char[escapedGroupLength];
	db.Escape(group, escapedGroup, escapedGroupLength);

	if(!InsertGroupWeight(db, escapedGroup)) return 0;

	if(!SelectGroupWeight(db, escapedGroup, point)) return 0;

	UMC_AddWeightModifier(1.0 + Pow(point * g_fPointMultiplierAmount, g_fPointExponentAmount));
	point += g_iPointAdditionAmount;
	
	if(!UpdateGroupWeight(db, escapedGroup, point)) return 0;

	delete db;

	return 0;
}

public void OnMapStart()
{
	Database db = connectToDatabase();
	if(db == null)
	{
		return;
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	char group[PLATFORM_MAX_PATH];
	UMC_GetCurrentMapGroup(group, sizeof(group));
	
	int escapedMapLength = strlen(map) * 2 + 1;
	char[] escapedMap = new char[escapedMapLength];
	db.Escape(map, escapedMap, escapedMapLength);

	int escapedGroupLength = strlen(group) * 2 + 1;
	char[] escapedGroup = new char[escapedGroupLength];
	db.Escape(group, escapedGroup, escapedGroupLength);

	if(!InsertMapWeight(db, escapedMap, escapedGroup)) return;

	if(!UpdateMapWeight(db, escapedMap, escapedGroup, 0)) return;

	if(!InsertGroupWeight(db, escapedGroup)) return;

	if(!UpdateGroupWeight(db, escapedGroup, 0)) return;

	delete db;
}

// DB

Database connectToDatabase()
{
	char error[255];
	Database db;
	
	if(SQL_CheckConfig("umc_weight"))
	{
		db = SQL_Connect("umc_weight", true, error, sizeof(error));
	}
	else
	{
		db = SQL_Connect("default", true, error, sizeof(error));
	}
	
	if(db == null)
	{
		LogError("Could not connect to database: %s", error);

		return db;
	}

	if(!SQL_FastQuery(db, "SET NAMES 'utf8mb4' COLLATE 'utf8mb4_unicode_ci'"))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		delete db;
		return null;
	}

	if(!db_createTableSuccess && (!SQL_FastQuery(db, db_createMapTable) || !SQL_FastQuery(db, db_createGroupTable)))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		delete db;
		return null;
	}

	db_createTableSuccess = true;
	
	return db;
}

bool InsertMapWeight(Database db, const char[] escapedMap, const char[] escapedGroup)
{
	char error[255];

	int queryStatementLength = sizeof(db_mapInsert) + strlen(escapedMap) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_mapInsert, escapedMap, escapedGroup);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool SelectMapWeight(Database db, const char[] escapedMap, const char[] escapedGroup, int &point)
{
	char error[255];

	int queryStatementLength = sizeof(db_mapSelect) + strlen(escapedMap) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_mapSelect, escapedMap, escapedGroup);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		point = SQL_FetchInt(hQuery, 0);
	}

	delete hQuery;

	return true;
}

bool UpdateMapWeight(Database db, const char[] escapedMap, const char[] escapedGroup, int point)
{
	char error[255];

	int queryStatementLength = sizeof(db_mapUpdate) + strlen(escapedMap) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_mapUpdate, point, escapedMap, escapedGroup);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool InsertGroupWeight(Database db, const char[] escapedGroup)
{
	char error[255];

	int queryStatementLength = sizeof(db_groupInsert) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_groupInsert, escapedGroup);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

bool SelectGroupWeight(Database db, const char[] escapedGroup, int &point)
{
	char error[255];

	int queryStatementLength = sizeof(db_groupSelect) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_groupSelect, escapedGroup);

	DBResultSet hQuery;

	if((hQuery = SQL_Query(db, queryStatement)) == null)
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	if(SQL_FetchRow(hQuery))
	{
		point = SQL_FetchInt(hQuery, 0);
	}

	delete hQuery;

	return true;
}

bool UpdateGroupWeight(Database db, const char[] escapedGroup, int point)
{
	char error[255];

	int queryStatementLength = sizeof(db_groupUpdate) + strlen(escapedGroup);
	char[] queryStatement = new char[queryStatementLength];
	Format(queryStatement, queryStatementLength, db_groupUpdate, point, escapedGroup);

	if(!SQL_FastQuery(db, queryStatement))
	{
		SQL_GetError(db, error, sizeof(error));
		LogError("Could not query to database: %s", error);

		return false;
	}

	return true;
}

// ConVars

public void CVC_PointAddition(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_iPointAdditionAmount = StringToInt(newValue);
}

public void CVC_PointMultiplier(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fPointMultiplierAmount = StringToFloat(newValue);
}

public void CVC_PointExponent(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fPointExponentAmount = StringToFloat(newValue);
}