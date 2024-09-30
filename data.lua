-- data.lua

-- Register the custom input (hotkey)
data:extend({
  {
    type = "custom-input",
    name = "toggle-agent-gui",
    key_sequence = "T", -- Set the desired hotkey here
    consuming = "none"
  }
})
