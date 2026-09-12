--[[--
BookRecap AI Provider Client.
Supports Groq, Gemini, OpenAI, DeepSeek, and local Ollama with zero-spoiler prompting.
--]]--

local logger = require("logger")

local API = {}
API.__index = API

-- JSON module resolver
local json = nil
local ok, mod = pcall(require, "json")
if ok and mod and mod.decode then
    json = mod
else
    ok, mod = pcall(require, "rapidjson")
    if ok and mod and mod.decode then
        json = mod
    end
end

local function encodeJSON(val)
    if json and json.encode then
        return json.encode(val)
    end
    -- Fallback basic JSON encoder for standard payloads
    if type(val) == "string" then
        return string.format('"%s"', val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', ''))
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local is_array = (#val > 0)
        local parts = {}
        if is_array then
            for idx, v in ipairs(val) do
                table.insert(parts, encodeJSON(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                table.insert(parts, string.format('"%s":%s', k, encodeJSON(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function decodeJSON(str)
    if json and json.decode then
        local ok_dec, res = pcall(json.decode, str)
        if ok_dec then return res end
    end
    return nil
end

function API:new(settings)
    local o = setmetatable({}, self)
    o.settings = settings
    return o
end

function API:sendChat(messages, system_prompt)
    local provider = self.settings:getProvider()
    local api_key = self.settings:getApiKey(provider)
    local model = self.settings:getModel()

    if provider ~= "ollama" and #api_key == 0 then
        return nil, string.format("API key for %s is not set. Go to Tools ➔ More tools ➔ BookRecap to enter it, or place %s_key.txt on your Kindle.", provider:upper(), provider)
    end

    local url
    local headers = { 'Content-Type: application/json' }
    local payload

    local all_messages = {}
    if system_prompt and #system_prompt > 0 then
        table.insert(all_messages, { role = "system", content = system_prompt })
    end
    for idx, m in ipairs(messages) do
        table.insert(all_messages, m)
    end

    if provider == "groq" then
        url = "https://api.groq.com/openai/v1/chat/completions"
        table.insert(headers, "Authorization: Bearer " .. api_key)
        payload = {
            model = model,
            messages = all_messages,
            temperature = 0.3,
            max_tokens = 600,
        }
    elseif provider == "gemini" then
        url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        table.insert(headers, "Authorization: Bearer " .. api_key)
        payload = {
            model = model,
            messages = all_messages,
            temperature = 0.3,
            max_tokens = 600,
        }
    elseif provider == "openai" then
        url = "https://api.openai.com/v1/chat/completions"
        table.insert(headers, "Authorization: Bearer " .. api_key)
        payload = {
            model = model,
            messages = all_messages,
            temperature = 0.3,
            max_tokens = 600,
        }
    elseif provider == "deepseek" then
        url = "https://api.deepseek.com/v1/chat/completions"
        table.insert(headers, "Authorization: Bearer " .. api_key)
        payload = {
            model = model,
            messages = all_messages,
            temperature = 0.3,
            max_tokens = 600,
        }
    elseif provider == "ollama" then
        local base = self.settings:getOllamaUrl():gsub("/+$", "")
        url = base .. "/api/chat"
        payload = {
            model = model,
            messages = all_messages,
            stream = false,
        }
    end

    local body_str = encodeJSON(payload)
    local safe_body = body_str:gsub("'", "'\\''")

    local header_args = ""
    for idx, h in ipairs(headers) do
        header_args = header_args .. string.format(' -H "%s"', h)
    end

    local curl_cmd = string.format(
        "curl -s -k -m 20 -X POST %s -d '%s' '%s' 2>/dev/null",
        header_args, safe_body, url
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        return nil, "Failed to execute network request. Ensure Wi-Fi is connected."
    end

    local raw = handle:read("*a")
    handle:close()

    if not raw or #raw == 0 then
        return nil, "No response from AI provider. Check your network or Wi-Fi connection."
    end

    local res = decodeJSON(raw)
    if not res then
        return nil, "Invalid response from server:\n" .. raw:sub(1, 200)
    end

    if res.error then
        local msg = (type(res.error) == "table" and res.error.message) or tostring(res.error)
        return nil, "API Error: " .. msg
    end

    -- OpenAI / Groq / Gemini / DeepSeek response format
    if res.choices and res.choices[1] and res.choices[1].message then
        return res.choices[1].message.content
    end

    -- Ollama response format
    if res.message and res.message.content then
        return res.message.content
    end

    return nil, "Unexpected response format:\n" .. raw:sub(1, 200)
end

-- Generate a strictly spoiler-guarded narrative recap
function API:getStoryRecap(book_title, book_author, chapter_title, cur_page, total_pages, sample_text)
    local system_prompt = [[
You are a thoughtful reading companion.
Your mission is to help a reader resume reading by summarizing what has happened so far.
STRICT CRITICAL RULES:
1. ABSOLUTELY ZERO SPOILERS for anything that happens AFTER the user's current reading point.
2. Only summarize established facts, key relationships, and events up to the stated chapter/page.
3. Be concise: provide 3 to 4 clear, high-impact bullet points.
4. If you are unsure of the exact timeline, stay broad and focus on the main premise without making up future events.
5. LANGUAGE: Always respond in the same language as the book (e.g. if the book title or text is in Serbian/Croatian/Bosnian, reply in natural Serbian; if English, reply in English).
]]

    local user_prompt = string.format(
        "I am reading '%s' by %s.\nI have currently reached %s (Page %d of %d).\n\nPlease give me a 3 to 4 bullet-point recap of the story developments up to this moment so I can jump back into reading with full context.",
        book_title or "Untitled",
        book_author or "Unknown Author",
        chapter_title or ("Page " .. tostring(cur_page)),
        cur_page or 1,
        total_pages or 1
    )

    if sample_text and #sample_text > 0 then
        user_prompt = user_prompt .. "\n\nExcerpt from where I left off:\n\"" .. sample_text:sub(1, 400) .. "\""
    end

    return self:sendChat({ { role = "user", content = user_prompt } }, system_prompt)
end

-- Identify a character strictly based on events up to the current chapter
function API:getCharacterInfo(book_title, book_author, chapter_title, char_name)
    local system_prompt = [[
You are an e-reader character guide.
The reader wants a quick reminder of who a character is without spoiling future chapters.
STRICT CRITICAL RULES:
1. Give a 2 to 3 sentence spoiler-free description of who this character is and their primary role/allegiance UP TO the specified chapter.
2. DO NOT reveal any upcoming betrayals, secret identities, deaths, or twists.
3. If this character was only just introduced, simply state what their initial role appears to be.
4. LANGUAGE: Always respond in the same language as the book (e.g. if the book title or text is in Serbian/Croatian/Bosnian, reply in natural Serbian; if English, reply in English).
]]

    local user_prompt = string.format(
        "Book: '%s' by %s\nCurrent Location: %s\nCharacter Name: '%s'\n\nWho is this character so far?",
        book_title or "Untitled",
        book_author or "Unknown Author",
        chapter_title or "Current Chapter",
        char_name
    )

    return self:sendChat({ { role = "user", content = user_prompt } }, system_prompt)
end

return API
