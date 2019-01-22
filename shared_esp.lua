-- Shared ESP by ShadyRetard

local NETWORK_CLIENT_URL = "csgo-radar.cf"
local NETWORK_GET_ADDR = "http://shady-aimware-api.cf/sharedesp";
local SCRIPT_FILE_NAME = GetScriptName();
local SCRIPT_FILE_ADDR = "https://raw.githubusercontent.com/hyperthegreat/aw_shared_esp/master/shared_esp.lua";
local VERSION_FILE_ADDR = "https://raw.githubusercontent.com/hyperthegreat/aw_shared_esp/master/version.txt";
local VERSION_NUMBER = "1.0.2";

local NETWORK_UPDATE_DELAY = 10;
local NETWORK_RETRIEVE_DELAY = 20;

local SHARED_ESP_ENABLE_TEAM_SHARE = gui.Checkbox(gui.Reference("MISC", "AUTOMATION", "Other"), "SHARED_ESP_ENABLE_TEAM_SHARE", "Shared ESP Team Location Sharing", false);
local SHARED_ESP_ENABLE_MESSAGE = gui.Checkbox(gui.Reference("MISC", "AUTOMATION", "Other"), "SHARED_ESP_ENABLE_MESSAGE", "Shared ESP Link Sharing", false);
local SHARED_ESP_MESSAGE_TEAM = gui.Checkbox(gui.Reference("MISC", "AUTOMATION", "Other"), "SHARED_ESP_MESSAGE_TEAM", "Shared ESP Global / Team message", false);
local SHARED_ESP_MESSAGE_TEAM_TEXT = gui.Text(gui.Reference("MISC", "AUTOMATION", "Other"), "Shared ESP Message Disabled");

local update_available = false;
local last_update_sent = globals.TickCount();
local last_update_retrieved = globals.TickCount();
local version_check_done = false;
local update_downloaded = false;

local entity_data = {};
local external_data = {};
local molotov_data = {};
local should_send_data = false;
local last_rounds = 0;
local has_shared_name = false;
local share_name = "";
local share_text = "";

function uiUpdateHandler()
    if (SHARED_ESP_MESSAGE_TEAM:GetValue() and share_text ~= "Shared ESP Global Message") then
        has_shared_name = false;
        share_text = "Shared ESP Global Message";
        SHARED_ESP_MESSAGE_TEAM_TEXT:SetText("Shared ESP Global Message");
    elseif (SHARED_ESP_MESSAGE_TEAM:GetValue() == false and share_text ~= "Shared ESP Team Message") then
        has_shared_name = false;
        share_text = "Shared ESP Team Message";
        SHARED_ESP_MESSAGE_TEAM_TEXT:SetText("Shared ESP Team Message");
    end
end

function updateEventHandler()
    if (update_available and not update_downloaded) then
        if (gui.GetValue("lua_allow_cfg") == false) then
            draw.Color(255, 0, 0, 255);
            draw.Text(0, 0, "[SHARED ESP] An update is available, please enable Lua Allow Config and Lua Editing in the settings tab");
        else
            local new_version_content = http.Get(SCRIPT_FILE_ADDR);
            local old_script = file.Open(SCRIPT_FILE_NAME, "w");
            old_script:Write(new_version_content);
            old_script:Close();
            update_available = false;
            update_downloaded = true;
        end
    end

    if (update_downloaded) then
        draw.Color(255, 0, 0, 255);
        draw.Text(0, 0, "[SHARED ESP] An update has automatically been downloaded, please reload the shared esp script");
        return;
    end

    if (not version_check_done) then
        if (gui.GetValue("lua_allow_http") == false) then
            draw.Color(255, 0, 0, 255);
            draw.Text(0, 0, "[SHARED ESP] Please enable Lua HTTP Connections in your settings tab to use this script");
            return;
        end

        version_check_done = true;
        local version = http.Get(VERSION_FILE_ADDR);
        if (version ~= VERSION_NUMBER) then
            update_available = true;
        end
    end
end

function drawEntitiesHandler()
    if (engine.GetServerIP() == nil) then
        return;
    end

    drawExternalPlayers();

    if (last_update_sent ~= nil and last_update_sent > globals.TickCount()) then
        last_update_sent = globals.TickCount();
    end

    if (last_update_retrieved ~= nil and last_update_retrieved > globals.TickCount()) then
        last_update_retrieved = globals.TickCount();
    end

    entity_data = {};

    addPlayers();
    addSmokes();
    addMolotovs();
    addC4();

    if (#entity_data == 0) then
        return;
    end

    if (globals.TickCount() - last_update_retrieved > NETWORK_RETRIEVE_DELAY) then
        http.Get(NETWORK_GET_ADDR .. "?ip=" .. urlencode(engine.GetServerIP()), handleGet);
        last_update_retrieved = globals.TickCount();
    end

    if (globals.TickCount() - last_update_sent > NETWORK_UPDATE_DELAY) then
        http.Get(NETWORK_GET_ADDR .. "/update" .. convertToQueryString(), handlePost);
        last_update_sent = globals.TickCount();
    end
end

function addPlayers()
    local players = entities.FindByClass("CCSPlayer");
    for i = 1, #players do
        local player = players[i];

        local self = entities.GetLocalPlayer();
        if (SHARED_ESP_ENABLE_TEAM_SHARE:GetValue() or (self ~= nil and player:GetTeamNumber() ~= self:GetTeamNumber())) then

            local dead = "false";
            if (not player:IsAlive()) then
                dead = "true";
            end

            local weapon_name = "none";
            local weapon = player:GetPropEntity('m_hActiveWeapon');
            if (weapon ~= nil) then
                weapon_name = weapon:GetName();
            end

            local px, py, pz = player:GetAbsOrigin();
            local angle = player:GetPropFloat("m_angEyeAngles[1]");

            table.insert(entity_data, {
                type = 'player',
                index = player:GetIndex(),
                team = player:GetTeamNumber(),
                name = player:GetName(),
                isDead = dead,
                position = {
                    x = px,
                    y = py,
                    z = pz,
                    angle = angle
                },
                hp = player:GetHealth(),
                maxHp = player:GetMaxHealth(),
                ping = entities.GetPlayerResources():GetPropInt("m_iPing", player:GetIndex());
                weapon = weapon_name
            });
        end
    end
end

function drawExternalPlayers()
    if (external_data == nil or #external_data == 0) then
        return;
    end

    local my_pid = client.GetLocalPlayerIndex();
    if (my_pid == nil) then
        return;
    end

    local spotted_pids = {};

    local players = entities.FindByClass("CCSPlayer");
    for i = 1, #players do
        local player = players[i];
        table.insert(spotted_pids, player:GetIndex());
    end

    for i, entity in ipairs(external_data) do
        local found = false;
        for y, id in ipairs(spotted_pids) do
            if (tonumber(id) == tonumber(entity.index)) then
                found = true;
            end
        end

        if (found == false) then
            local screen_x, screen_y = client.WorldToScreen(entity.position.x, entity.position.y, entity.position.z);
            local w, h = draw.GetTextSize(entity.name);
            if (screen_x ~= nil and w ~= nil) then
                draw.Text(screen_x - (w / 2), screen_y - (h / 2) - 10, entity.name);
            end
        end
    end
end

function addSmokes()
    local active_smokes = entities.FindByClass("CSmokeGrenadeProjectile");
    for i = 1, #active_smokes do
        local smoke = active_smokes[i];
        local sx, sy, sz = smoke:GetAbsOrigin();
        local smokeTick = smoke:GetProp("m_nSmokeEffectTickBegin");
        if (smokeTick ~= 0 and (globals.TickCount() - smokeTick) * globals.TickInterval() < 17.5) then
            table.insert(entity_data, {
                type = 'active_smoke',
                index = smoke:GetIndex(),
                position = {
                    x = sx,
                    y = sy,
                    z = sz
                },
                time = (globals.TickCount() - smokeTick) * globals.TickInterval()
            });
        end
    end
end

function addMolotovs()
    local active_molotovs = entities.FindByClass("CInferno");
    for i = 1, #active_molotovs do
        local molotov = active_molotovs[i];
        local sx, sy, sz = molotov:GetAbsOrigin();
        local molotov_found = false;

        for index, entity in ipairs(molotov_data) do
            if (entity.index == molotov:GetIndex()) then
                molotov_data[index].time = (globals.TickCount() - entity.startTick) * globals.TickInterval();

                molotov_found = true;
                break;
            end
        end

        if (molotov_found == false) then
            table.insert(molotov_data, {
                type = 'active_molotov',
                index = molotov:GetIndex(),
                position = {
                    x = sx,
                    y = sy,
                    z = sz
                },
                time = 0,
                startTick = globals.TickCount()
            });
        end
    end

    for index, molotov in ipairs(molotov_data) do
        table.insert(entity_data, molotov);
    end
end

function addC4()
    local carriedC4 = entities.FindByClass("CC4")[1];
    local plantedC4 = entities.FindByClass("CPlantedC4")[1];

    if (carriedC4 ~= nil) then
        local cx, cy, cz = carriedC4:GetAbsOrigin();
        table.insert(entity_data, {
            type = 'c4',
            index = carriedC4:GetIndex(),
            position = {
                x = cx,
                y = cy,
                z = cz
            },
            time = 0
        });
    end

    if (plantedC4 ~= nil) then
        local cx, cy, cz = plantedC4:GetAbsOrigin();
        table.insert(entity_data, {
            type = 'c4',
            index = plantedC4:GetIndex(),
            position = {
                x = cx,
                y = cy,
                z = cz
            },
            time = plantedC4:GetPropFloat("m_flDefuseCountDown")
        });
    end
end

function handleGet(content)
    if (content == nil or content == "ok" or content == "error") then
        return;
    end

    external_data = convertToTable(content);
end

function handlePost(content)
    if (content == nil or content == "error") then
        return;
    end

    if (share_name ~= content) then
        share_name = content;
        has_shared_name = false;
        print("Live game radar at " .. NETWORK_CLIENT_URL .. "/" .. share_name);

        if (SHARED_ESP_ENABLE_MESSAGE:GetValue() == false) then
            return;
        end
    end

    if (SHARED_ESP_ENABLE_MESSAGE:GetValue() == true and has_shared_name == false) then
        if (SHARED_ESP_MESSAGE_TEAM:GetValue() == true) then
            client.ChatSay("Live game radar at " .. NETWORK_CLIENT_URL .. "/" .. share_name);
        else
            client.ChatTeamSay("Live game radar at " .. NETWORK_CLIENT_URL .. "/" .. share_name);
        end
        has_shared_name = true;
    end
end

function gameEventHandler(event)
    if (event:GetName() == "round_start") then
        should_send_data = true;
        entity_data = {
            {
                type = "round_start\t",
                position = {}
            }
        };
        http.Get(NETWORK_GET_ADDR .. convertToQueryString());
    end

    if (event:GetName() == "round_end") then
        should_send_data = false;
    end

    if (event:GetName() == "inferno_expire" or event:GetName() == "inferno_extinguish") then
        for index, molotov in ipairs(molotov_data) do
            if molotov.index == event:GetInt("entityid") then
                table.remove(molotov_data, index);
            end
        end
    end
end

function convertToTable(content)
    local data = {};

    local strings_to_parse = {};
    for i in string.gmatch(content, "([^\n]*)\n") do
        table.insert(strings_to_parse, i);
    end

    for i = 1, #strings_to_parse do
        local matches = {};

        for word in string.gmatch(strings_to_parse[i], "([^\t]*)") do
            table.insert(matches, word);
        end

        table.insert(data, {
            type = matches[1],
            index = tonumber(matches[2]),
            team = tonumber(matches[3]),
            name = matches[4],
            isDead = matches[5],
            position = {
                x = tonumber(matches[6]),
                y = tonumber(matches[7]),
                z = tonumber(matches[8]),
                angle = tonumber(matches[9])
            },
            hp = tonumber(matches[10]),
            maxHp = tonumber(matches[11]),
            ping = tonumber(matches[12]),
            weapon = matches[13]
        });
    end

    return data;
end

function convertToQueryString()
    local temp = {};
    local queryString = "&data[]=";
    for i, entity in ipairs(entity_data) do
        if (entity ~= nil) then

            if (entity.type == "player") then
                table.insert(temp,
                    urlencode(table.concat({
                        entity.type,
                        entity.index,
                        entity.team,
                        entity.name,
                        entity.isDead,
                        entity.position.x,
                        entity.position.y,
                        entity.position.z,
                        entity.position.angle,
                        entity.hp,
                        entity.maxHp,
                        entity.ping,
                        entity.weapon,
                        globals.CurTime()
                    }, "\t")));
            end

            if (entity.type == "active_smoke" or entity.type == "active_molotov") then
                table.insert(temp,
                    urlencode(table.concat({
                        entity.type,
                        entity.index,
                        entity.position.x,
                        entity.position.y,
                        entity.position.z,
                        entity.time,
                        globals.CurTime()
                    }, "\t")));
            end

            if (entity.type == "c4") then
                table.insert(temp,
                    urlencode(table.concat({
                        entity.type,
                        entity.index,
                        entity.position.x,
                        entity.position.y,
                        entity.position.z,
                        entity.time,
                        globals.CurTime()
                    }, "\t")));
            end
        end
    end

    local rounds = 0;
    local teams = entities.FindByClass("CTeam");
    for i, team in ipairs(teams) do
        rounds = rounds + team:GetPropInt('m_scoreTotal');
    end

    if (rounds ~= last_rounds or not should_send_data) then
        last_rounds = rounds;
        temp = {};
    end

    return "?ip=" .. urlencode(engine.GetServerIP()) .. "&mapName=" .. engine.GetMapName() .. "&rounds=" .. last_rounds .. queryString .. table.concat(temp, '&data[]=');
end

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

function urlencode(url)
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w ])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

client.AllowListener("round_start");
client.AllowListener("round_end");
client.AllowListener("inferno_expire");
client.AllowListener("inferno_extinguish");
callbacks.Register("Draw", uiUpdateHandler);
callbacks.Register("Draw", updateEventHandler);
callbacks.Register("Draw", drawEntitiesHandler);
callbacks.Register("FireGameEvent", gameEventHandler);