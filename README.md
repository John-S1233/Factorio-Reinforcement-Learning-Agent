# Factorio Reinforcement Learning Agent 

## Overview

This project is a Factorio mod that integrates a reinforcement learning (RL) agent into the game. The agent can learn to optimize various in-game production processes, maximizing resource gathering, building efficiency, and automation. The mod leverages Lua scripting to extract in-game data, which is used to train the RL agent.

## Features

- **Reinforcement Learning Integration**: The RL agent interacts with the Factorio environment and receives rewards based on game metrics such as production rates or resource collection.
- **In-Game Data Extraction**: The mod collects data from the Factorio game state, such as objects, items, terrain, and other environmental features, to provide the RL agent with information for decision-making.
- **Optimization of Production Processes**: The agent learns to control the production chains and optimize them to meet specified goals (e.g., maximizing item output or minimizing resource waste).
  
## File Descriptions

- **control.lua**: Contains the main logic of the RL agent, responsible for extracting data from the game and sending actions based on the agent's decisions.
- **data.lua**: Manages the data configurations for the Factorio mod.
- **serpent.lua**: A Lua serialization library used for encoding and decoding game data for communication between the game environment and the RL agent.
- **info.json**: Contains metadata about the mod, such as name, version, and description.

## Installation

1. Download the mod and extract the contents into your Factorio mods folder.
2. Ensure that the mod is enabled in the game’s mod settings.
3. Start a new game or load an existing save, and the RL agent will begin interacting with the game environment.

## Requirements

- **Factorio version**: Ensure your Factorio installation is compatible with this mod (check the `info.json` file for version details).
- **Lua**: This mod uses Lua scripting for the integration of the RL agent.

## Future Improvements

- Enhanced agent behavior for more complex decision-making.
- Support for more in-game metrics and reward functions.
- Visualization of the agent's learning progress and decisions in-game.

## Contributing

Feel free to contribute by submitting pull requests or reporting issues. Improvements to the RL agent or the integration with Factorio are highly encouraged.
