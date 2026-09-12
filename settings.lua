--[[--
BookRecap Settings Manager.
Handles persistent configuration in G_reader_settings, offline cache, and zero-typing key import.
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local Settings = {}
Settings.__index = Settings

local DEFAULT_MODELS = {
    groq = "openai/gpt-oss-120b",
    gemini = "gemini-3.5-flash-lite",
    openai = "gpt-4o-mini",
    deepseek = "deepseek-chat",
    ollama = "llama3.2",
}

function Settings:new()
    local o = setmetatable({}, self)
    return o
end

function Settings:get(key, default)
    if not G_reader_settings then return default end
    local val = G_reader_settings:readSetting("bookrecap_" .. key)
    if val ~= nil then return val end
    return default
end

function Settings:save(key, val)
    if not G_reader_settings then return end
    G_reader_settings:saveSetting("bookrecap_" .. key, val)
end

function Settings:getProvider()
    return self:get("provider", "groq")
end

function Settings:setProvider(p)
    self:save("provider", p)
end

local function detectProviderForKey(key)
    if key:sub(1, 4) == "gsk_" then
        return "groq"
    elseif key:sub(1, 4) == "AIza" then
        return "gemini"
    elseif key:sub(1, 3) == "sk-" then
        return "openai"
    end
    return nil
end

function Settings:getApiKey(prov)
    prov = prov or self:getProvider()
    local val = self:get("api_key_" .. prov, "")
    if val and #val > 0 then
        return val
    end
    -- Fallback to legacy generic api_key if matching provider
    local legacy = self:get("api_key", "")
    if legacy and #legacy > 0 then
        if prov == "groq" and legacy:sub(1, 4) == "gsk_" then return legacy end
        if prov == "gemini" and legacy:sub(1, 4) == "AIza" then return legacy end
        if prov == "openai" and legacy:sub(1, 3) == "sk-" then return legacy end
        if prov == self:getProvider() then return legacy end
    end
    return ""
end

function Settings:setApiKey(key, prov)
    prov = prov or self:getProvider()
    self:save("api_key_" .. prov, key)
    if prov == self:getProvider() then
        self:save("api_key", key)
    end
end

function Settings:getModel()
    local prov = self:getProvider()
    return self:get("model_" .. prov, DEFAULT_MODELS[prov] or "llama-3.3-70b-versatile")
end

function Settings:setModel(m)
    local prov = self:getProvider()
    self:save("model_" .. prov, m)
end

function Settings:getOllamaUrl()
    return self:get("ollama_url", "http://192.168.1.50:11434")
end

function Settings:setOllamaUrl(u)
    self:save("ollama_url", u)
end

-- Offline Cache for Characters & Recaps
function Settings:getCachedCharacter(book_title, char_name)
    local cache = self:get("cache_characters", {})
    local book_cache = cache[book_title]
    return book_cache and book_cache[char_name:lower()]
end

function Settings:saveCachedCharacter(book_title, char_name, bio)
    local cache = self:get("cache_characters", {})
    if not cache[book_title] then cache[book_title] = {} end
    cache[book_title][char_name:lower()] = bio
    self:save("cache_characters", cache)
end

function Settings:getCachedRecap(book_title, chapter_str)
    local cache = self:get("cache_recaps", {})
    local book_cache = cache[book_title]
    return book_cache and book_cache[chapter_str]
end

function Settings:saveCachedRecap(book_title, chapter_str, recap_text)
    local cache = self:get("cache_recaps", {})
    if not cache[book_title] then cache[book_title] = {} end
    cache[book_title][chapter_str] = recap_text
    self:save("cache_recaps", cache)
end

-- Import API keys from Kindle root (/mnt/us/) or KOReader data dir.
-- Supports groq_key.txt, gemini_key.txt, openai_key.txt, and multi-line ai_key.txt
function Settings:importKeyFromFile()
    local imported = {}
    local files_found = {}

    local specific_files = {
        { path = "/mnt/us/groq_key.txt", prov = "groq" },
        { path = DataStorage:getFullDataDir() .. "/groq_key.txt", prov = "groq" },
        { path = "/mnt/us/gemini_key.txt", prov = "gemini" },
        { path = DataStorage:getFullDataDir() .. "/gemini_key.txt", prov = "gemini" },
        { path = "/mnt/us/openai_key.txt", prov = "openai" },
        { path = DataStorage:getFullDataDir() .. "/openai_key.txt", prov = "openai" },
        { path = "/mnt/us/deepseek_key.txt", prov = "deepseek" },
        { path = DataStorage:getFullDataDir() .. "/deepseek_key.txt", prov = "deepseek" },
    }

    for idx, item in ipairs(specific_files) do
        if lfs.attributes(item.path, "mode") == "file" then
            local f = io.open(item.path, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content and #content > 0 then
                    local clean_key = content:gsub("[\r\n%s]+", "")
                    if #clean_key > 5 then
                        self:setApiKey(clean_key, item.prov)
                        imported[item.prov] = clean_key
                        table.insert(files_found, item.path)
                        pcall(os.remove, item.path)
                    end
                end
            end
        end
    end

    local generic_files = {
        "/mnt/us/ai_key.txt",
        DataStorage:getFullDataDir() .. "/ai_key.txt",
    }

    for idx, path in ipairs(generic_files) do
        if lfs.attributes(path, "mode") == "file" then
            local f = io.open(path, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content and #content > 0 then
                    table.insert(files_found, path)
                    for line in content:gmatch("[^\r\n]+") do
                        local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                        local prov_match, key_match = clean:match("^([%a_]+)%s*=%s*(.+)$")
                        if prov_match and key_match then
                            prov_match = prov_match:lower()
                            key_match = key_match:gsub("[\r\n%s]+", "")
                            if #key_match > 5 then
                                self:setApiKey(key_match, prov_match)
                                imported[prov_match] = key_match
                            end
                        elseif #clean > 5 then
                            local detected = detectProviderForKey(clean)
                            if detected then
                                self:setApiKey(clean, detected)
                                imported[detected] = clean
                            else
                                local cur_prov = self:getProvider()
                                self:setApiKey(clean, cur_prov)
                                imported[cur_prov] = clean
                            end
                        end
                    end
                    pcall(os.remove, path)
                end
            end
        end
    end

    local count = 0
    for k, v in pairs(imported) do count = count + 1 end
    if count > 0 then
        return true, imported, files_found
    end
    return false, nil, nil
end

return Settings
