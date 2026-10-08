# Mod Sync

Keeps everyone's MultiMC modpack in sync with this repo. Players get a popup when mods are added/updated/removed, click **Yes**, and it downloads them.

## For players
1. Download **ModSync.zip** (from the Discord guide or `https://github.com/ItsKauai/server-mod-pack/raw/main/ModSync.zip`) and **Extract All**.
2. Double-click **Install.bat**, type the number of your 26.2 instance.
3. Open MultiMC with the **"MultiMC + Mod Sync"** desktop shortcut from now on.

| File | What it does |
|---|---|
| `Install.bat` | Finds MultiMC, lets you pick the instance, sets up Mod Sync + the desktop shortcut (press **C** in the first 5 seconds to re-pick) |
| `remove_mod_sync.bat` | Turns Mod Sync off for the instance(s) you pick (mods stay) |
| `forget_previous_instance_selected.bat` | Forgets the remembered instance so Install.bat asks again |
| `resources/` | The scripts the .bat files run (`ModSync.ps1` is the updater; `LaunchMultiMC.ps1` is the shortcut) |

## For the pack owner
After changing the `mods/` folder, run `admin/Publish-Manifest.ps1` (see the comments at the top of it), then commit and push.
The live updater that players self-update from is `tool/ModSync.ps1` at the repo root. `Publish-Manifest.ps1` keeps it in sync with `ModSync/resources/ModSync.ps1`.