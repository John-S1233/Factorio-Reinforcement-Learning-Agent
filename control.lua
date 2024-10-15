-- control.lua
local serpent = require("serpent")

-- Observation radius for nearby entities
local OBSERVATION_RADIUS = 100

-- Initialize global variables
script.on_init(function()
    global.agents = {} -- Table to hold agents
    global.agent_id_counter = 0 -- Counter to assign unique IDs to agents
    global.training_active = false
    global.training_event_registered = false
    global.persistent_agents = false -- Whether to maintain a persistent number of agents
    global.desired_agent_count = 0 -- Desired number of agents to maintain
    global.total_production = {} -- Track total production of items
end)

-- Function to unlock all technologies for a given force
local function unlock_all_technologies(force)
    for _, tech in pairs(force.technologies) do
        tech.researched = true
        for _, effect in pairs(tech.effects) do
            if effect.type == "unlock-recipe" then
                force.recipes[effect.recipe].enabled = true
            end
        end
    end
end

-- Function to create agents
local function create_agents(player, num_agents)
    local surface = player.surface
    local position = player.position
    local force = player.force

    -- Unlock all technologies for the player's force
    unlock_all_technologies(force)

    for i = 1, num_agents do
        -- Increment agent ID counter
        global.agent_id_counter = global.agent_id_counter + 1
        local agent_id = global.agent_id_counter

        -- Spawn the agent character near the player
        local spawn_position = {x = position.x + i * 2, y = position.y}
        local character = surface.create_entity{name = "character", position = spawn_position, force = agent_force}

        -- Give starting items to the agent
        local inventory = character.get_main_inventory()
        inventory.insert{name = "burner-mining-drill", count = 1}
        inventory.insert{name = "stone-furnace", count = 1}
        inventory.insert{name = "iron-plate", count = 8} -- Initial resources

        -- Initialize agent data
        global.agents[agent_id] = {
            id = agent_id,
            character = character,
            Q = {},
            state = nil,
            action = nil,
            learning_rate = 0.1,
            discount_factor = 0.9,
            exploration_rate = 0.1,
            target_item = "iron-gear-wheel",
            components = {},
            total_reward = 0,
            placed_entities = {},
        }
    end
    player.print(num_agents .. " agents have been created.")
end

-- Function to delete all agents
local function delete_agents(player)
    for agent_id, agent in pairs(global.agents) do
        if agent.character and agent.character.valid then
            agent.character.destroy()
        end
        -- Destroy placed entities
        for _, entity in pairs(agent.placed_entities or {}) do
            if entity and entity.valid then
                entity.destroy()
            end
        end
    end
    global.agents = {}
    global.agent_id_counter = 0
    global.total_production = {}
    player.print("All agents have been deleted.")
end


-- Function to manage agent persistence
local function maintain_agent_count(player)
    if global.persistent_agents and global.desired_agent_count > 0 then
        local alive_agents = 0
        for _, agent in pairs(global.agents) do
            if agent.character and agent.character.valid then
                alive_agents = alive_agents + 1
            end
        end
        local agents_needed = global.desired_agent_count - alive_agents
        if agents_needed > 0 then
            player.print("Respawning " .. agents_needed .. " agents to maintain desired count.")
            create_agents(player, agents_needed)
        end
    end
end

-- Function to craft a random item
local function craft_random_item(agent)
    local character = agent.character
    if not character or not character.valid then return end

    local inventory = character.get_main_inventory()
    local recipes = character.force.recipes
    local craftable_items = {}
    for name, recipe in pairs(recipes) do
        if recipe.enabled and recipe.category == "crafting" then
            local can_craft = true
            -- Check if the agent has the required ingredients
            for _, ingredient in pairs(recipe.ingredients) do
                if ingredient.type ~= "item" then
                    can_craft = false
                    break
                end
                local count = inventory.get_item_count(ingredient.name)
                if count < ingredient.amount then
                    can_craft = false
                    break
                end
            end
            -- Check if the recipe produces items only
            for _, product in pairs(recipe.products) do
                if product.type ~= "item" then
                    can_craft = false
                    break
                end
            end
            if can_craft then
                table.insert(craftable_items, name)
            end
        end
    end
    if #craftable_items > 0 then
        local item_name = craftable_items[math.random(#craftable_items)]
        local recipe = recipes[item_name]
        -- Consume ingredients
        for _, ingredient in pairs(recipe.ingredients) do
            inventory.remove{name=ingredient.name, count=ingredient.amount}
        end
        -- Add result
        for _, product in pairs(recipe.products) do
            inventory.insert{name=product.name, count=product.amount}
            -- Update global production
            global.total_production[product.name] = (global.total_production[product.name] or 0) + product.amount
        end
    end
end

-- Function to place a random item from the inventory
local function place_random_item(agent)
    local character = agent.character
    if not character or not character.valid then return end

    local surface = character.surface
    local inventory = character.get_main_inventory()
    local items = inventory.get_contents()
    local placeable_items = {}
    for name, count in pairs(items) do
        local item_proto = game.item_prototypes[name]
        if item_proto and item_proto.place_result then
            table.insert(placeable_items, name)
        end
    end
    if #placeable_items > 0 then
        local item_name = placeable_items[math.random(#placeable_items)]
        local item_proto = game.item_prototypes[item_name]
        if inventory.remove{name=item_name, count=1} == 1 then
            local position = {x = character.position.x + math.random(-1, 1), y = character.position.y + math.random(-1, 1)}
            local can_place = surface.can_place_entity{
                name = item_proto.place_result.name,
                position = position,
                force = character.force
            }
            if can_place then
                local placed_entity = surface.create_entity{
                    name = item_proto.place_result.name,
                    position = position,
                    force = character.force,
                    raise_built = true
                }
                -- Store the placed entity
                agent.placed_entities = agent.placed_entities or {}
                table.insert(agent.placed_entities, placed_entity)
            else
                -- Can't place here, return the item to inventory
                inventory.insert{name=item_name, count=1}
            end
        end
    end
end

-- Function to interact with nearby chests
local function interact_with_chest(agent, action_type)
    local character = agent.character
    if not character or not character.valid then return end

    local surface = character.surface
    local position = character.position
    local nearby_chests = surface.find_entities_filtered{
        area = {
            {position.x - OBSERVATION_RADIUS, position.y - OBSERVATION_RADIUS},
            {position.x + OBSERVATION_RADIUS, position.y + OBSERVATION_RADIUS}
        },
        type = "container"
    }

    if #nearby_chests == 0 then return end

    -- Choose a random chest to interact with
    local chest = nearby_chests[math.random(#nearby_chests)]
    local chest_inventory = chest.get_inventory(defines.inventory.chest)
    local character_inventory = character.get_main_inventory()

    if action_type == "take" then
        -- Take a random item from the chest
        local chest_contents = chest_inventory.get_contents()
        local items = {}
        for name, count in pairs(chest_contents) do
            table.insert(items, name)
        end
        if #items > 0 then
            local item_name = items[math.random(#items)]
            if chest_inventory.remove{name=item_name, count=1} == 1 then
                character_inventory.insert{name=item_name, count=1}
            end
        end
    elseif action_type == "put" then
        -- Put a random item into the chest
        local character_contents = character_inventory.get_contents()
        local items = {}
        for name, count in pairs(character_contents) do
            table.insert(items, name)
        end
        if #items > 0 then
            local item_name = items[math.random(#items)]
            if character_inventory.remove{name=item_name, count=1} == 1 then
                chest_inventory.insert{name=item_name, count=1}
            end
        end
    elseif action_type == "view" then
    end
end

-- Function to execute an action
local function execute_action(agent, action)
    local character = agent.character
    if not character or not character.valid then return end

    if action == "move_north" then
        character.walking_state = {walking = true, direction = defines.direction.north}
        character.direction = defines.direction.north
    elseif action == "move_south" then
        character.walking_state = {walking = true, direction = defines.direction.south}
        character.direction = defines.direction.south
    elseif action == "move_east" then
        character.walking_state = {walking = true, direction = defines.direction.east}
        character.direction = defines.direction.east
    elseif action == "move_west" then
        character.walking_state = {walking = true, direction = defines.direction.west}
        character.direction = defines.direction.west
    elseif action == "mine" then
        local surface = character.surface
        local position = character.position
        -- Find entities in front of the character
        local direction = character.direction
        local target_position = {x = position.x, y = position.y}
        if direction == defines.direction.north then
            target_position.y = target_position.y - 1
        elseif direction == defines.direction.east then
            target_position.x = target_position.x + 1
        elseif direction == defines.direction.south then
            target_position.y = target_position.y + 1
        elseif direction == defines.direction.west then
            target_position.x = target_position.x - 1
        end
        local entities = surface.find_entities_filtered{position = target_position, force = "neutral"}
        for _, entity in pairs(entities) do
            if entity.valid and entity.minable and character.can_reach_entity(entity) then
                -- Get inventory before mining
                local inventory = character.get_main_inventory()
                local pre_mine_contents = inventory.get_contents()
                -- Mine the entity
                character.mine_entity(entity)
                -- Get inventory after mining
                local post_mine_contents = inventory.get_contents()
                -- Calculate the difference
                for item_name, count in pairs(post_mine_contents) do
                    local pre_count = pre_mine_contents[item_name] or 0
                    local added = count - pre_count
                    if added > 0 then
                        global.total_production[item_name] = (global.total_production[item_name] or 0) + added
                    end
                end
                break
            end
        end
    elseif action == "idle" then
        character.walking_state = {walking = false}
    elseif action == "craft_item" then
        craft_random_item(agent)
    elseif action == "place_item" then
        place_random_item(agent)
    elseif action == "take_from_chest" then
        interact_with_chest(agent, "take")
    elseif action == "put_in_chest" then
        interact_with_chest(agent, "put")
    elseif action == "view_chest" then
        interact_with_chest(agent, "view")
    end
end


-- Function to get all components recursively
local function get_all_components(item_name, components)
    components = components or {}
    local recipe = game.recipe_prototypes[item_name]
    if recipe then
        for _, ingredient in pairs(recipe.ingredients) do
            if ingredient.type == "item" then
                if not components[ingredient.name] then
                    components[ingredient.name] = true
                    get_all_components(ingredient.name, components)
                end
            end
        end
    end
    return components
end

-- Function to calculate the global reward
local function get_global_reward()
    local target_item = nil
    for _, agent in pairs(global.agents) do
        target_item = agent.target_item
        break
    end
    if not target_item then return 0 end

    -- Get total production of the target item and its components
    local total_reward = 0
    local target_amount = global.total_production[target_item] or 0
    total_reward = total_reward + target_amount * 2.0 

    -- Get all components
    local all_components = get_all_components(target_item)
    for component_name, _ in pairs(all_components) do
        local component_amount = global.total_production[component_name] or 0
        total_reward = total_reward + component_amount * 1.0 
    end

    -- Reset total production after calculating reward
    global.total_production = {}

    return total_reward
end

-- Function to get the current state
local function get_current_state(agent)
    local character = agent.character
    if not character or not character.valid then return nil end

    local position = character.position

    -- Inventory summary
    local inventory_contents = character.get_main_inventory().get_contents()
    local inventory_summary = {}
    for name, count in pairs(inventory_contents) do
        inventory_summary[name] = count
    end

    -- Nearby entities
    local surface = character.surface
    local area = {
        {position.x - OBSERVATION_RADIUS, position.y - OBSERVATION_RADIUS},
        {position.x + OBSERVATION_RADIUS, position.y + OBSERVATION_RADIUS}
    }
    local nearby_entities = surface.find_entities_filtered{area = area}
    local entity_counts = {}

    for _, entity in pairs(nearby_entities) do
        local entity_name = entity.name
        entity_counts[entity_name] = (entity_counts[entity_name] or 0) + 1
    end

    -- Limit the entity counts to prevent state explosion
    local limited_entity_counts = {}
    for name, count in pairs(entity_counts) do
        if game.entity_prototypes[name].type == "resource" or
           game.entity_prototypes[name].type == "tree" or
           game.entity_prototypes[name].type == "simple-entity" or
           game.entity_prototypes[name].type == "container" then
            limited_entity_counts[name] = count
        end
    end

    local state = {
        x = math.floor(position.x + 0.5),
        y = math.floor(position.y + 0.5),
        inventory = inventory_summary,
        nearby_entities = limited_entity_counts,
    }
    return state
end

-- Function to choose an action based on the current state
local function choose_action(agent, state)
    local state_key = serpent.line(state) -- Serialize the state to a string key
    local Q = agent.Q

    -- Initialize Q-values for this state if not present
    if not Q[state_key] then
        Q[state_key] = {}
        -- Define the action space
        local actions = {
            "move_north", "move_south", "move_east", "move_west",
            "mine", "idle",
            "craft_item", "place_item",
            "take_from_chest", "put_in_chest", "view_chest"
        }
        for _, action in pairs(actions) do
            Q[state_key][action] = 0
        end
    end

    -- Exploration vs. Exploitation
    if math.random() < agent.exploration_rate then
        local actions = {}
        for action, _ in pairs(Q[state_key]) do
            table.insert(actions, action)
        end
        return actions[math.random(#actions)]
    else
        -- Exploit: choose the best action
        local max_value = -math.huge
        local best_actions = {}
        for action, value in pairs(Q[state_key]) do
            if value > max_value then
                max_value = value
                best_actions = {action}
            elseif value == max_value then
                table.insert(best_actions, action)
            end
        end
        -- Randomly select among the best actions
        return best_actions[math.random(#best_actions)]
    end
end

-- Function to update the Q-table
local function update_q_table(agent, state, action, reward, next_state)
    local state_key = serpent.line(state)
    local next_state_key = serpent.line(next_state)
    local Q = agent.Q
    
    if not Q[next_state_key] then
        Q[next_state_key] = {}

        local actions = {
            "move_north", "move_south", "move_east", "move_west",
            "mine", "idle",
            "craft_item", "place_item",
            "take_from_chest", "put_in_chest", "view_chest"
        }
        for _, a in pairs(actions) do
            Q[next_state_key][a] = 0
        end
    end

    -- Q-learning update rule
    local old_value = Q[state_key][action]
    local max_next_value = -math.huge
    for _, value in pairs(Q[next_state_key]) do
        if value > max_next_value then
            max_next_value = value
        end
    end

    local learning_rate = agent.learning_rate
    local discount_factor = agent.discount_factor

    local new_value = old_value + learning_rate * (reward + discount_factor * max_next_value - old_value)
    Q[state_key][action] = new_value
end

-- Training loop
local function training_step(event)
    -- Execute actions for all agents first
    for agent_id, agent in pairs(global.agents) do
        if agent.character and agent.character.valid then
            local state = get_current_state(agent)
            if state then
                local action = choose_action(agent, state)
                execute_action(agent, action)
                -- Store state and action for later Q-table update
                agent.state = state
                agent.action = action
            end
        else
            -- Agent's character is invalid (dead), remove agent
            global.agents[agent_id] = nil
            game.print("Agent " .. agent_id .. " has died and has been removed.")
        end
    end

    -- Calculate global reward after all actions have been executed
    local global_reward = get_global_reward()

    -- Update Q-tables for all agents with the global reward
    for _, agent in pairs(global.agents) do
        if agent.state and agent.action then
            local next_state = get_current_state(agent)
            update_q_table(agent, agent.state, agent.action, global_reward, next_state)
            -- Accumulate total reward
            agent.total_reward = agent.total_reward + global_reward
            -- Clear stored state and action
            agent.state = nil
            agent.action = nil
        end
    end

    -- Maintain agent count if persistent agents are enabled
    if global.persistent_agents then
        maintain_agent_count(game.get_player(1))
    end
end

-- Function to start training
local function start_training(player)
    global.training_active = true
    player.print("Training started.")
    if not global.training_event_registered then
        global.training_event_registered = true
        script.on_nth_tick(10, training_step)
    end
end

-- Function to stop training
local function stop_training(player)
    global.training_active = false
    player.print("Training stopped.")
    if global.training_event_registered then
        script.on_nth_tick(60, nil)
        global.training_event_registered = false
    end
end

-- Function to deploy the agent
local function deploy_agent(player)
    player.print("Agents deployed.")
    -- Set exploration rate to 0 to only exploit learned policy
    for _, agent in pairs(global.agents) do
        agent.exploration_rate = 0.0
    end
end

-- Function to create the agent GUI
local function create_agent_gui(player)
    local gui = player.gui.screen
    if gui.agent_gui == nil then
        local frame = gui.add{type="frame", name="agent_gui", direction="vertical", caption="RL Agent Control"}
        frame.location = {x = 100, y = 100}

        -- Add a flow container for the buttons and input fields
        local flow = frame.add{type="flow", direction="horizontal"}

        -- Start Training button
        flow.add{type="button", name="start_training_button", caption="Start Training"}

        -- Stop Training button
        flow.add{type="button", name="stop_training_button", caption="Stop Training"}

        -- Deploy Agent button
        flow.add{type="button", name="deploy_agent_button", caption="Deploy Agents"}

        -- Reset Model button
        flow.add{type="button", name="reset_model_button", caption="Reset Model"}

        -- Print Highest Reward button
        flow.add{type="button", name="print_highest_reward_button", caption="Print Highest Reward"}

        -- Number of Agents input field
        frame.add{type="textfield", name="num_agents_input", text="1"}
        frame.add{type="label", caption="Enter the number of agents to create."}

        -- Create Agents button
        frame.add{type="button", name="create_agents_button", caption="Create Agents"}

        -- Delete Agents button
        frame.add{type="button", name="delete_agents_button", caption="Delete Agents"}

        -- Persistent Agents checkbox
        frame.add{type="checkbox", name="persistent_agents_checkbox", caption="Maintain Agent Count", state=false}
        frame.add{type="label", caption="Check to keep the specified number of agents alive."}

        -- Target Item input field
        frame.add{type="textfield", name="target_item_input", text="iron-gear-wheel"}
        frame.add{type="label", caption="Enter the target item name for the agents to optimize."}

        -- Update Target Item button
        frame.add{type="button", name="update_target_item_button", caption="Set Target Item"}

        frame.add{type="label", name="status_label", caption="Status: Idle"}

        -- Make the GUI draggable
        local dragger = frame.add{type="empty-widget", style="draggable_space_header", direction="horizontal"}
        dragger.drag_target = frame
        dragger.style.horizontally_stretchable = true
        dragger.style.height = 24
    end
end

-- Function to toggle the agent GUI
local function toggle_agent_gui(player)
    local gui = player.gui.screen.agent_gui
    if gui then
        gui.destroy()
    else
        create_agent_gui(player)
    end
end

-- Event handler for GUI click events
script.on_event(defines.events.on_gui_click, function(event)
    local element = event.element
    local player = game.get_player(event.player_index)
    local gui = player.gui.screen.agent_gui

    if element.name == "start_training_button" then
        if gui.status_label then
            gui.status_label.caption = "Status: Training..."
        end
        start_training(player)
    elseif element.name == "stop_training_button" then
        if gui.status_label then
            gui.status_label.caption = "Status: Idle"
        end
        stop_training(player)
    elseif element.name == "deploy_agent_button" then
        if gui.status_label then
            gui.status_label.caption = "Status: Agents Deployed"
        end
        deploy_agent(player)
    elseif element.name == "reset_model_button" then
        -- Reset the agents' Q-tables and total rewards
        for _, agent in pairs(global.agents) do
            agent.Q = {}
            agent.total_reward = 0
            agent.placed_entities = {}
        end
        global.total_production = {}
        player.print("Agents' models have been reset.")
        if gui.status_label then
            gui.status_label.caption = "Status: Models Reset"
        end
    elseif element.name == "print_highest_reward_button" then
        -- Find the agent with the highest total reward
        local highest_reward = -math.huge
        local best_agent_id = nil
        for agent_id, agent in pairs(global.agents) do
            if agent.total_reward > highest_reward then
                highest_reward = agent.total_reward
                best_agent_id = agent_id
            end
        end
        if best_agent_id then
            player.print("Agent " .. best_agent_id .. " has the highest total reward: " .. highest_reward)
        else
            player.print("No agents found.")
        end
    elseif element.name == "create_agents_button" then
        local num_agents = tonumber(gui.num_agents_input.text)
        if num_agents and num_agents > 0 then
            global.desired_agent_count = num_agents
            create_agents(player, num_agents)
        else
            player.print("Please enter a valid number of agents.")
        end
    elseif element.name == "delete_agents_button" then
        delete_agents(player)
        if gui.status_label then
            gui.status_label.caption = "Status: Agents Deleted"
        end
    elseif element.name == "update_target_item_button" then
        local target_item = gui.target_item_input.text
        if game.item_prototypes[target_item] then
            -- Update target item for all agents
            for _, agent in pairs(global.agents) do
                agent.target_item = target_item
                agent.components = {} 
            end
            player.print("Target item updated to: " .. target_item)
        else
            player.print("Invalid item name: " .. target_item)
        end
    end
end)

-- Event handler for GUI checkbox state changes
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local element = event.element
    if element.name == "persistent_agents_checkbox" then
        global.persistent_agents = element.state
        if global.persistent_agents then
            game.get_player(event.player_index).print("Persistent agents enabled.")
        else
            game.get_player(event.player_index).print("Persistent agents disabled.")
        end
    end
end)

-- Event handler for the hotkey to toggle the GUI
script.on_event("toggle-agent-gui", function(event)
    local player = game.get_player(event.player_index)
    toggle_agent_gui(player)
end)
