# Factorio Reinforcement Learning Agent Mod

![Untitledvideo-MadewithClipchamp2-ezgif com-speed](https://github.com/user-attachments/assets/33f5be03-efdf-4532-8f3d-e54e1b4f4e98)
*Image: Agents being trained*
## Overview

This project is a Factorio mod that integrates a reinforcement learning (RL) agent into the game. The agent can learn to optimize various in-game production processes, maximizing resource gathering, building efficiency, and automation. The mod leverages Lua scripting to extract in-game data, which is used to train the RL agent.

Due to Factorio's modding system, the use of traditional machine learning techniques like convolutional neural networks (CNNs) was not feasible, as Lua lacks the necessary machine learning libraries and computational capacity required for such models. Instead, this mod employs a simpler Q-learning algorithm that fits within Factorio's modding framework, allowing the agent to learn efficiently without external dependencies.

## Features

- **Reinforcement Learning Integration**: The RL agent interacts with the Factorio environment and receives rewards based on game metrics such as production rates or resource collection.
- **In-Game Data Extraction**: The mod collects data from the Factorio game state, such as objects, items, terrain, and other environmental features, to provide the RL agent with information for decision-making.
- **Optimization of Production Processes**: The agent learns to control the production chains and optimize them to meet specified goals (e.g., maximizing item output or minimizing resource waste).

## How the RL Agent Learns (Q-Learning)

### Q-Learning Algorithm

This mod implements the **Q-learning** algorithm, a simple and effective model-free RL technique. Q-learning is based on the idea of learning a value function \( Q(s, a) \), which represents the expected reward for taking action \( a \) in state \( s \). The agent updates this value function over time through its interactions with the Factorio game environment.

1. **State Representation**: The state \( s \) is a representation of the current in-game situation, including the available resources, the status of production lines, and the positions of machines.
2. **Actions**: The agent chooses from a set of actions, such as placing or adjusting machines, optimizing resource flow, or rearranging production belts. Each action affects the in-game environment.
3. **Reward**: After each action, the agent receives a reward based on the result of its action. For example, if an action leads to higher production output or a more efficient resource flow, the agent receives a positive reward. Conversely, inefficient actions are penalized with negative rewards.
4. **Learning Process**: The agent updates its Q-values using the Q-learning update rule:
   
   ![0_ZC1PGJlwSfruMxTw](https://github.com/user-attachments/assets/016b53c1-c646-422e-9bf0-9e25c4244a18)

   Over time, the agent learns to take actions that maximize the cumulative reward, improving its performance in optimizing Factorio's production processes.

### Why CNNs Were Not Used

Although CNNs are powerful for handling complex visual data and could be useful for analyzing Factorio's intricate game world, they were not feasible in this mod due to Factorio's modding system, which runs entirely in Lua. Lua lacks the necessary libraries and computational frameworks (such as TensorFlow or PyTorch) to support deep learning models like CNNs. Moreover, Factorio's modding environment does not have access to the hardware (e.g., GPUs) that deep learning models typically require for training and inference.

Therefore, Q-learning was chosen as a lightweight, effective alternative that fits well within the constraints of Factorio’s Lua-based modding system.

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
