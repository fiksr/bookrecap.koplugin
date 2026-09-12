--[[--
BookRecap Settings Manager.
Handles persistent configuration in G_reader_settings, offline cache, and zero-typing key import.
--]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local Settings = {}
Settings.__index = Settings

local DEFAULT_MODELS = {
    groq = "llama-3.3-70b-versatile",
    gemini = "gemini-1.5-flash",
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

function Settings:getApiKey()
    return self:get("api_key", "")
end

function Settings:setApiKey(key)
    self:save("api_key", key)
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

-- Convenience helper: Import API key from /mnt/us/ai_key.txt or /mnt/us/groq_key.txt
function Settings:importKeyFromFile()
    local candidate_paths = {
        "/mnt/us/ai_key.txt",
        "/mnt/us/groq_key.txt",
        "/mnt/us/gemini_key.txt",
        DataStorage:getFullDataDir() .. "/ai_key.txt",
    }

    for _, path in ipairs(candidate_paths) do
        if lfs.attributes(path, "mode") == "file" then
            local f = io.open(path, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content and #content > 0 then
                    local clean_key = content:gsub("[\r\n%s]+", "")
                    if #clean_key > 5 then
                        self:setApiKey(clean_key)
                        -- Auto-detect Groq keys (start with gsk_)
                        if clean_key:sub(1, 4) == "gsk_" then
                            self:setProvider("groq")
                        end
                        -- Remove temporary file for security
                        pcall(os.remove, path)
                        return true, path, clean_key
                    end
                end
            end
        end
    end
    return false, nil, nil
end

return Settings
