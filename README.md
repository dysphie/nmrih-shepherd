<p align="center">
  <img src="https://i.imgur.com/PExkibt.png" />
</p>

<h1 align="center">[NMRiH] Shepherd</h1>

This plugin adds commands to deal with situations where players are missing from a checkpoint that requires everyone to proceed.

## Player Commands

- `sm_missing [target]`: Shows who is missing from a checkpoint that requires everyone.
  - `target` (optional): Username of a player in the checkpoint. Defaults to the command issuer or the spectated player.

## Admin Commands

- `sm_ultimatum [target] [time] [action]`: Forces all players to be in a required checkpoint within a time limit or face consequences. Players will see a chat message, and the checkpoint will be highlighted in red.
  - `target` (optional): Username of a player in the checkpoint. Defaults to the command issuer or the spectated player.
  - `time` (optional): Time limit in seconds. Defaults to `sm_shepherd_ultimate_default_seconds`.
  - `action` (optional): Action to take on missing players:
    - `tp`: Teleports the missing players to the required zone.
    - `strip`: Teleports the missing players to the required zone without their inventory.
    - `kill`: Kills the missing players instantly.
    - Defaults to `sm_shepherd_ultimate_default_action`.

- `sm_checkpoints`: Toggles displaying all mandatory checkpoints along with their IDs on the screen. This can help with [Automation](#Automation).

## ConVars

ConVars can be configured in `cfg/sourcemod/shepherd.cfg`:

- `sm_shepherd_ultimatum_sound`: Specifies the sound file to be played during an ultimatum.

- `sm_shepherd_ultimatum_default_action`: Sets the default action to be taken on missing players when no action type is specified via a command. Defaults to `"tp"` (teleport).

- `sm_shepherd_ultimatum_default_seconds`: Specifies the default waiting time, in seconds, for missing players when no duration is specified via a command. Defaults to `120` seconds.

- `sm_shepherd_highlight_bounds`: Whether to display the checkpoint's bounding box when highlighted. Defaults to `1` (enabled).

## Automation

The plugin can automatically issue ultimatums for certain checkpoints when they are touched by a player for the first time. 
To enable automation for a checkpoint, edit `addons/sourcemod/configs/shepherd_triggers.txt`. The config file has one line for each checkpoint with the following format:

```
[map name] [trigger id] [seconds] [action]
```

Examples: 
```cpp
// Kill players who aren't in the elevator after 1 minute
nmo_ghostbuster 473061 60 kill 

// Teleport lost players to the lift after 2 minutes
nmo_ishimura_task_v3 865320 120 tp
```

## Installation

To install this plugin, follow these steps:

- Download the latest release from [here](https://github.com/dysphie/nmrih-shepherd/releases).
- Extract the zip file and copy the contents to your `addons/sourcemod` folder.
- Load the plugin: `sm plugins load shepherd` in the console.
- Reload translations: `sm_reload_translations` in the console.
