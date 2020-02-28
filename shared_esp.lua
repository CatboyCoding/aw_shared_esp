-- Shared ESP by ShadyRetard
-- V5 Support by GenoSans
local NETWORK_CLIENT_URL = "radar.shadyretard.io"
local NETWORK_API_ADDR = "http://api.shadyretard.io";
local SHAREDESP_CLOSEST_ADDR = NETWORK_API_ADDR;
local SCRIPT_FILE_NAME = GetScriptName();

local window = gui.Window("shared_esp", "Shared ESP", 50, 50, 250, 210)

local retrieve_delay = gui.Slider(window, "retrieve_delay", "Update Delay", 25, 25, 100);
local update_delay = gui.Slider(window, "update_delay", "Retrieve Delay", 35, 35, 100);

local message_team = gui.Combobox(window, "message_team", "Link Sharing", "None", "Team", "Global");

local link_url = "No radar available.";
local link_text = gui.Text(window, "No radar available.");

local ok = false;

function updateWindowHandler()
    
    window:SetActive(gui.Reference("MENU"):IsActive())
end

local last_update_sent = globals.TickCount();
local last_update_retrieved = globals.TickCount();

local entity_data = {};
local external_data = {};
local molotov_data = {};
local should_send_data = true;
local last_rounds = 0;
local has_shared_name = false;
local share_name = "";
local share_text = "";

local available_api_servers;
local server_retrieval_started = false;
local server_picker_done = false;

local server_latencies = {};

function serverPickerHandler()
    if (server_retrieval_started == false and (available_api_servers == nil or #available_api_servers == 0)) then
        server_retrieval_started = true;
        http.Get(NETWORK_API_ADDR .. "/routing/servers", function(response)
            if (response == nil or response == "error") then
                server_retrieval_started = false;
                return;
            end

            available_api_servers = {};
            for word in string.gmatch(response, "[^,]+") do
                table.insert(available_api_servers, word);
            end

            for i=1, #available_api_servers do
                http.Get(available_api_servers[i] .. "/routing/latency?time=" .. globals.CurTime(), function(latency_response)
                    local latency;
                    if (latency_response == nil or latency_response == "error") then
                        latency = "error"
                    else
                        latency = globals.CurTime() - latency_response;
                    end
                    table.insert(server_latencies, {
                        name = available_api_servers[i],
                        latency = latency;
                    });

                    if (#server_latencies == #available_api_servers) then
                        local lowest_latency_server = NETWORK_API_ADDR;
                        local lowest_latency = 99999;
                        for y=1, #server_latencies do
                            if (server_latencies[y].latency < lowest_latency) then
                                lowest_latency = server_latencies[y].latency;
                                lowest_latency_server = server_latencies[y].name
                            end
                        end
                        SHAREDESP_CLOSEST_ADDR = lowest_latency_server;
                        server_picker_done = true;
                    end
                end);
            end
        end);
    end
end

function drawEntitiesHandler()
    if (engine.GetServerIP() == nil or server_picker_done == false) then
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

    if (globals.TickCount() - last_update_retrieved > retrieve_delay:GetValue()) then
        http.Get(SHAREDESP_CLOSEST_ADDR .. "/sharedesp" .. "?ip=" .. urlencode(engine.GetServerIP()), handleGet);
        last_update_retrieved = globals.TickCount();
    end

    if (globals.TickCount() - last_update_sent > update_delay:GetValue()) then
        http.Get(SHAREDESP_CLOSEST_ADDR .. "/sharedesp" .. "/update" .. convertToQueryString(), handlePost);
        last_update_sent = globals.TickCount();
    end
end

function addPlayers()
    local players = entities.FindByClass("CCSPlayer");
    for i = 1, #players do
        local player = players[i];

        local self == entities.GetLocalPlayer();

        if(self ~= nil && player:GetTeamNumber() == self:GetTeamNumber()) continue

        local dead = "false";
        if (not player:IsAlive()) then
            dead = "true";
        end
        
        local weapon_name = "weapon_none";
        local weapon = player:GetPropEntity('m_hActiveWeapon');
        if (weapon ~= nil) then
            weapon_name = weapon:GetName();
        end
        
        if(weapon_name == nil) then
            weapon_name = "weapon_unknown"
        end

        weapon_name = string.gsub(weapon_name, "weapon_", "")
        
        local p = player:GetAbsOrigin();
        local angle = player:GetPropFloat("m_angEyeAngles[1]");
        
        table.insert(entity_data, {
            type = 'player',
            index = player:GetIndex(),
            team = player:GetTeamNumber(),
            name = player:GetName(),
            isDead = dead,
            position = {
                x = p.x,
                y = p.y,
                z = p.z,
                angle = angle
            },
            hp = player:GetHealth(),
            maxHp = player:GetMaxHealth(),
            ping = entities.GetPlayerResources():GetPropInt("m_iPing", player:GetIndex());
            weapon = weapon_name
        });
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
            if(entity == nil or entity.position == nil or entity.position.x == nil) then
                return
            end

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
        link_url = NETWORK_CLIENT_URL .. "/" .. share_name;
        link_text:SetText(link_url);

        if (message_team:GetValue() == "None") then
            return;
        end
    end

    if (has_shared_name == false) then
        if (message_team:GetValue() == "Team") then
            client.ChatTeamSay("Live game radar @ " .. link_url);
        elseif (message_team:GetValue() == "Global") then
            client.ChatSay("Live game radar @ " .. link_url);
        end
        has_shared_name = true;
    end
end

function gameEventHandler(event)
    if (server_picker_done == false) then
        return;
    end

    if (event:GetName() == "round_start") then
        should_send_data = true;
        entity_data = {
            {
                type = "round_start\t",
                position = {}
            }
        };
        http.Get(SHAREDESP_CLOSEST_ADDR .. "/sharedesp" .. convertToQueryString());
    end

    if (event:GetName() == "round_end") then
        link_url = "No radar available.";
        link_text:SetText(link_url);
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
                if(entity.weapon == nil) then entity.weapon = "wtf" end
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
callbacks.Register("Draw", serverPickerHandler);
callbacks.Register("Draw", drawEntitiesHandler);
callbacks.Register("Draw", updateWindowHandler);
callbacks.Register("FireGameEvent", gameEventHandler);
