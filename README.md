# GS Orchestrator

A simple orchestrator script for game servers. Initially created for srcds server management, this should also work well for other games.

This script was made with reflink-capable filesystems like BTRFS and XFS in mind, depending on very quick file copies through reflinks. If your filesystem does not support it, you are likely better off with another tool.

## Features

- Very lightweight & small script
- Flexible
- Isolated environments for servers through reflink copies

## Prerequisites

- tmux (for default config)

## Usage

The script works on root directories which represent individual game installations. These directories should contain the following structure:

```
tf2/
    1. common/ (contains base files)
        00-base/
        10-plugins/
        ...
    2. modules/ (contains modules specifiable by each config)
        cool_plugins/
        intense_plugins/
        ...
    3. configs/ (contains the actual server configs)
        vanilla/
        modded/
        ...
    4. overlays/ (optional)
        localtesting/
```

Files inside the subdirectories are copied over into the subfolder representing the final server state inside the run directory, in descending order. So all files residing in `common` first, then selected `modules`, then the `config` and at last all `overlays`.

Modules are specified inside a `modules.txt` file inside the server config subdirectory, each one seperated by newline.

```sh
tf2/configs/modded/modules.txt

cool_plugins
intense_plugins
```

The script relies on 2 user-specified external scripts per game installation, `start.sh` and `update.sh`. The first one is called on server activation, the second one when requesting an update of a game installation.

Examples for TF2:

```sh
tf2/configs/vanilla/start.sh

#!/bin/sh

./srcds_run -game tf +maxplayers 24 +map ctf_2fort +ip 0.0.0.0 -port 27015"
```

```sh
tf2/update.sh

#!/bin/sh

./steamcmd/steamcmd.sh +runscript $PWD/tf2_ds.txt
```

```sh
tf2/tf2_ds.txt

@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
login anonymous
force_install_dir ../common/00-base
app_update 232250 validate
quit
```

You can run `./orchestrator.sh <game>` to get a list of commands. To update your base game installation run `./orchestrator.sh <game> update`, and to set up & start up all servers run `./orchestrator.sh <game> start "*"`.

Servers are rebuilt on server start or when explicitly running `./orchestrator.sh <game> apply`.

With the default config, running servers are attachable to through tmux with the name $game_$server, e.g. `tf2_vanilla`. You can adjust all the scripts to your liking though!

## FAQ

### How do I keep persistent state over server restarts?

Use symlinks to another directory like `persistent/` inside the game installation directory for the corresponding files / folders to prevent them from being erased on server start.
