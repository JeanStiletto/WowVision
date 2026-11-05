local module = WowVision.base.windows.mail

-- Classic clients (Vanilla, TBC, Mists) poll MailFrame; the send tab itself
-- lives in core. Bail out on a client without the Classic mail frames.
if not SendMailFrame then
    return
end

-- Override core's PlayerInteractionWindow with a TBC-standard FrameWindow.
-- PlayerInteractionWindow opens on event before frames are fully initialized;
-- FrameWindow polls visibility, matching all other TBC modules.
module:unregisterWindow("mail")

module:registerWindow({
    type = "FrameWindow",
    name = "mail",
    frameName = "MailFrame",
    conflictingAddons = { "Sku" },
    graphScreen = { render = module.renderMail },
})
