--[[--
BookRecap Main Plugin for KOReader.
Provides spoiler-free narrative recaps and character identification directly within the reading experience.
--]]--

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

-- Safe submodule loader
local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
local Settings = dofile(plugin_dir .. "settings.lua")
local API = dofile(plugin_dir .. "api.lua")
local Dialog = dofile(plugin_dir .. "dialog.lua")

-- Register into KOReader's menu order system
local function addToMenuOrder(module_path, section, name)
    local ok, order = pcall(require, module_path)
    if ok and order and order[section] then
        for i, v in ipairs(order[section]) do
            if v == name then return end
        end
        table.insert(order[section], name)
    end
end
addToMenuOrder("ui/elements/reader_menu_order", "more_tools", "bookrecap")
addToMenuOrder("ui/elements/filemanager_menu_order", "more_tools", "bookrecap")

local BookRecap = WidgetContainer:extend{
    name = "bookrecap",
    is_doc_only = false,
}

function BookRecap:init()
    self.settings = Settings:new()
    self.api = API:new(self.settings)

    -- Hook into the Reader's highlight dialog for character lookups
    if self.ui and self.ui.highlight then
        self:addToHighlightDialog()
    end

    -- Register into KOReader's main menu
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

-- Safely get book metadata
function BookRecap:getBookContext()
    local doc = self.ui and self.ui.document
    local props = (doc and doc.getProps and doc:getProps()) or (self.ui and self.ui.doc_props) or {}

    local title = props.display_title or props.title or (doc and doc.file and doc.file:match("([^/]+)%.%w+$")) or "Untitled"
    local author = props.authors or props.author or "Unknown Author"

    local t_part, a_part = title:match("^(.-)%s+[%-–—]%s+(.+)$")
    if t_part and a_part and #t_part > 0 and #a_part > 0 then
        title = t_part
        if not author or author == "Unknown Author" or #author == 0 then
            author = a_part
        end
    end

    local chapter_title = nil
    if self.ui and self.ui.toc and self.ui.toc.getTocTitleOfCurrentPage then
        local ok_ct, ct = pcall(function() return self.ui.toc:getTocTitleOfCurrentPage() end)
        if ok_ct and ct and #ct > 0 then
            chapter_title = ct:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    local cur_page = (self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage())
                  or (self.ui and self.ui.view and self.ui.view.footer and self.ui.view.footer.pageno)
                  or 1
    local total_pages = (self.ui and self.ui.view and self.ui.view.footer and self.ui.view.footer.pages)
                     or (doc and doc.getPageCount and doc:getPageCount())
                     or 1

    return title, author, chapter_title, cur_page, total_pages
end

function BookRecap:addToHighlightDialog()
    -- 01_who_is_this places our button right at the top of the highlight action popup
    self.ui.highlight:addToHighlightDialog("01_who_is_this", function(this)
        return {
            text = _("Who is this?"),
            callback = function()
                this:highlightFromHoldPos()
                if not (this.selected_text and this.selected_text.text) then return end

                local char_name = util.cleanupSelectedText(this.selected_text.text):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                if #char_name == 0 then return end
                this:onClose(true)

                self:onIdentifyCharacter(char_name)
            end,
        }
    end)
end

function BookRecap:onIdentifyCharacter(char_name)
    local title, author, chapter_title, cur_page, total_pages = self:getBookContext()
    local location_str = chapter_title or string.format("Page %d of %d", cur_page, total_pages)

    -- Check offline cache first
    local cached = self.settings:getCachedCharacter(title, char_name)
    if cached and #cached > 0 then
        Dialog.showCharacter(char_name, title, location_str .. " (Offline Cache)", cached)
        return
    end

    -- Query AI provider
    local loading = Dialog.showLoading(string.format(_("Consulting companion about '%s'..."), char_name))

    UIManager:scheduleIn(0.1, function()
        local bio, err = self.api:getCharacterInfo(title, author, location_str, char_name)
        Dialog.closeLoading(loading)

        if bio and #bio > 0 then
            self.settings:saveCachedCharacter(title, char_name, bio)
            Dialog.showCharacter(char_name, title, location_str, bio)
        else
            UIManager:show(InfoMessage:new{
                text = string.format(_("Could not identify '%s':\n%s"), char_name, tostring(err or "Unknown error")),
                timeout = 5,
            })
        end
    end)
end

function BookRecap:onCatchMeUp()
    local title, author, chapter_title, cur_page, total_pages = self:getBookContext()
    local location_str = chapter_title or string.format("Page %d of %d", cur_page, total_pages)

    local cached = self.settings:getCachedRecap(title, location_str)
    if cached and #cached > 0 then
        Dialog.showRecap(title, location_str .. " (Offline Cache)", cached)
        return
    end

    local loading = Dialog.showLoading(_("Preparing spoiler-free story recap..."))

    UIManager:scheduleIn(0.1, function()
        local recap, err = self.api:getStoryRecap(title, author, chapter_title, cur_page, total_pages, nil)
        Dialog.closeLoading(loading)

        if recap and #recap > 0 then
            self.settings:saveCachedRecap(title, location_str, recap)
            Dialog.showRecap(title, location_str, recap)
        else
            UIManager:show(InfoMessage:new{
                text = string.format(_("Could not generate recap:\n%s"), tostring(err or "Unknown error")),
                timeout = 5,
            })
        end
    end)
end

function BookRecap:addToMainMenu(menu_items)
    menu_items.bookrecap = {
        text = _("BookRecap"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
        sub_item_table = self:getSubMenuItems(),
    }
end

function BookRecap:getSubMenuItems()
    local prov = self.settings:getProvider()
    return {
        {
            text = _("📖 Catch Me Up (Spoiler-Free Recap)"),
            enabled = self.ui and self.ui.document and true or false,
            callback = function()
                self:onCatchMeUp()
            end,
        },
        {
            text = _("📥 Import API Keys from Kindle Storage"),
            callback = function()
                local ok, imported, files = self.settings:importKeyFromFile()
                if ok then
                    local lines = { _("Keys imported successfully:") }
                    for prov, key in pairs(imported) do
                        local mask = #key > 8 and (key:sub(1, 4) .. "..." .. key:sub(-4)) or key
                        table.insert(lines, string.format("• %s: %s", prov:upper(), mask))
                    end
                    table.insert(lines, "\n" .. _("You can switch between Groq and Gemini anytime!"))
                    UIManager:show(InfoMessage:new{
                        text = table.concat(lines, "\n"),
                        timeout = 6,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = _("No key files found on Kindle storage (/mnt/us/).\n\nYou can place any of these files via USB:\n• groq_key.txt (your Groq key)\n• gemini_key.txt (your Gemini key)\n• ai_key.txt (single key or groq=... / gemini=...)\n\nThen tap this button again!"),
                        timeout = 8,
                    })
                end
            end,
        },
        {
            text_func = function()
                return string.format(_("🤖 Provider: %s (%s)"), self.settings:getProvider():upper(), self.settings:getModel())
            end,
            sub_item_table = {
                {
                    text = _("Groq (Free & Blazing Fast)"),
                    checked_func = function() return self.settings:getProvider() == "groq" end,
                    callback = function() self.settings:setProvider("groq") end,
                },
                {
                    text = _("Google Gemini"),
                    checked_func = function() return self.settings:getProvider() == "gemini" end,
                    callback = function() self.settings:setProvider("gemini") end,
                },
                {
                    text = _("OpenAI (GPT-4o-mini)"),
                    checked_func = function() return self.settings:getProvider() == "openai" end,
                    callback = function() self.settings:setProvider("openai") end,
                },
                {
                    text = _("DeepSeek (DeepSeek Chat)"),
                    checked_func = function() return self.settings:getProvider() == "deepseek" end,
                    callback = function() self.settings:setProvider("deepseek") end,
                },
                {
                    text = _("Local Ollama (100% Offline via LAN)"),
                    checked_func = function() return self.settings:getProvider() == "ollama" end,
                    callback = function() self.settings:setProvider("ollama") end,
                },
            },
        },
        {
            text_func = function()
                return string.format(_("🧠 Model: %s"), self.settings:getModel())
            end,
            sub_item_table_func = function()
                local prov = self.settings:getProvider()
                if prov == "gemini" then
                    return {
                        {
                            text = _("Gemini 3.5 Flash-Lite (500 RPD Free)"),
                            checked_func = function() return self.settings:getModel() == "gemini-3.5-flash-lite" end,
                            callback = function() self.settings:setModel("gemini-3.5-flash-lite") end,
                        },
                        {
                            text = _("Gemini 2.5 Flash (20 RPD Free / Paid)"),
                            checked_func = function() return self.settings:getModel() == "gemini-2.5-flash" end,
                            callback = function() self.settings:setModel("gemini-2.5-flash") end,
                        },
                        {
                            text = _("Gemini 3.8 Flash"),
                            checked_func = function() return self.settings:getModel() == "gemini-3.8-flash" end,
                            callback = function() self.settings:setModel("gemini-3.8-flash") end,
                        },
                        {
                            text = _("Gemini 3.7 Flash"),
                            checked_func = function() return self.settings:getModel() == "gemini-3.7-flash" end,
                            callback = function() self.settings:setModel("gemini-3.7-flash") end,
                        },
                        {
                            text = _("Gemini 3.6 Flash"),
                            checked_func = function() return self.settings:getModel() == "gemini-3.6-flash" end,
                            callback = function() self.settings:setModel("gemini-3.6-flash") end,
                        },
                    }
                elseif prov == "groq" then
                    return {
                        {
                            text = _("GPT-OSS 120B (Recommended — 1K RPD, Best Quality)"),
                            checked_func = function() return self.settings:getModel() == "openai/gpt-oss-120b" end,
                            callback = function() self.settings:setModel("openai/gpt-oss-120b") end,
                        },
                        {
                            text = _("Qwen 3.8 27B (1K RPD — Strong Reasoning)"),
                            checked_func = function() return self.settings:getModel() == "qwen/qwen3.8-27b" end,
                            callback = function() self.settings:setModel("qwen/qwen3.8-27b") end,
                        },
                        {
                            text = _("GPT-OSS 20B (1K RPD — Fast & Lightweight)"),
                            checked_func = function() return self.settings:getModel() == "openai/gpt-oss-20b" end,
                            callback = function() self.settings:setModel("openai/gpt-oss-20b") end,
                        },
                        {
                            text = _("Groq Compound (250 RPD)"),
                            checked_func = function() return self.settings:getModel() == "groq/compound" end,
                            callback = function() self.settings:setModel("groq/compound") end,
                        },
                    }
                end
                return {
                    {
                        text = string.format(_("Current: %s"), self.settings:getModel()),
                        enabled = false,
                    },
                }
            end,
        },
        {
            text_func = function()
                local prov = self.settings:getProvider()
                local cur_key = self.settings:getApiKey(prov)
                local status = (#cur_key > 0) and _("✓ configured") or _("✗ not set")
                return string.format(_("⌨️ %s Key (%s)"), prov:upper(), status)
            end,
            callback = function()
                local prov = self.settings:getProvider()
                local cur_key = self.settings:getApiKey(prov)
                local dialog
                dialog = InputDialog:new{
                    title = string.format(_("Enter %s API Key"), prov:upper()),
                    input = cur_key,
                    input_hint = prov == "groq" and "gsk_..." or (prov == "gemini" and "AIza..." or "API Key"),
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dialog) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local val = dialog:getInputText():gsub("[\r\n%s]+", "")
                                    self.settings:setApiKey(val, prov)
                                    UIManager:close(dialog)
                                    UIManager:show(InfoMessage:new{
                                        text = string.format(_("%s Key saved!"), prov:upper()),
                                        timeout = 2,
                                    })
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text = _("🧹 Clear Offline Cache"),
            callback = function()
                self.settings:save("cache_characters", {})
                self.settings:save("cache_recaps", {})
                UIManager:show(InfoMessage:new{ text = _("Offline cache cleared."), timeout = 2 })
            end,
        },
    }
end

return BookRecap
