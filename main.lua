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
        for _, v in ipairs(order[section]) do
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
            text = _("📥 Import Key from /mnt/us/ai_key.txt"),
            callback = function()
                local ok, path, key = self.settings:importKeyFromFile()
                if ok then
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("API Key imported successfully from:\n%s\n(Provider set to %s)"), path, self.settings:getProvider():upper()),
                        timeout = 4,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = _("No ai_key.txt found on Kindle root (/mnt/us/ai_key.txt).\n\nCreate this file on your computer, paste your key, and tap this again!"),
                        timeout = 6,
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
                    text = _("Groq (Free & Blazing Fast — Llama 3.3)"),
                    checked_func = function() return self.settings:getProvider() == "groq" end,
                    callback = function() self.settings:setProvider("groq") end,
                },
                {
                    text = _("Google Gemini (Free Tier — Gemini 1.5 Flash)"),
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
            text = _("⌨️ Enter API Key Manually"),
            callback = function()
                local cur_key = self.settings:getApiKey()
                local mask = #cur_key > 8 and (cur_key:sub(1, 4) .. "..." .. cur_key:sub(-4)) or cur_key
                local dialog
                dialog = InputDialog:new{
                    title = _("Enter AI Provider API Key"),
                    input = cur_key,
                    input_hint = _("e.g. gsk_... or AIzaSy..."),
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
                                    self.settings:setApiKey(val)
                                    UIManager:close(dialog)
                                    UIManager:show(InfoMessage:new{ text = _("API Key saved!"), timeout = 2 })
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
