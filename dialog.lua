--[[--
BookRecap Dialog Presentation.
Presents spoiler-free recaps and character biographies using KOReader's native TextViewer.
--]]--

local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Dialog = {}

function Dialog.showLoading(msg)
    local info = InfoMessage:new{
        text = msg or _("Consulting reading companion..."),
    }
    UIManager:show(info)
    return info
end

function Dialog.closeLoading(info_widget)
    if info_widget then
        UIManager:close(info_widget)
    end
end

function Dialog.showRecap(book_title, chapter_str, recap_text)
    local title = string.format(_("📖 Story Recap: %s"), book_title)
    local full_text = string.format(
        "📍 Current Progress: %s\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n%s\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n⚠️ Strictly spoiler-guarded up to this point.",
        chapter_str or "Current Reading Point",
        recap_text
    )

    local viewer = TextViewer:new{
        title = title,
        text = full_text,
        text_type = "general",
    }
    UIManager:show(viewer)
end

function Dialog.showCharacter(char_name, book_title, chapter_str, bio_text)
    local title = string.format(_("👤 Character Guide: %s"), char_name)
    local full_text = string.format(
        "📖 Book: %s\n📍 Location: %s\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n%s\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n⚠️ Strictly spoiler-guarded up to this chapter.",
        book_title or "Current Book",
        chapter_str or "Current Chapter",
        bio_text
    )

    local viewer = TextViewer:new{
        title = title,
        text = full_text,
        text_type = "general",
    }
    UIManager:show(viewer)
end

return Dialog
