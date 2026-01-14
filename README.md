# TwoPoint Evidence Standalone (SQL-only)

Standalone forensics/evidence system with:
- Evidence drops (casings, blood, fingerprints, touch DNA)
- Scanner collection (no inventory items; bags are stored in SQL)
- Multi-location labs (analyze/delete restricted to labs)
- Configurable lab blips
- BigDaddy Chat `/chatname` sync for evidence profile display names
- LB-Phone wiretap tab (monitors call events; alerts LEOs when tapped numbers are involved)

## Dependencies
- oxmysql
- PoliceEMSActivity (patched to provide exports:IsOnDuty on server, and statebag `LocalPlayer.state.pea_onDuty`)
- BigDaddy-Chat (for name sync export `getPlayerName`)
- lb-phone (optional, for wiretap call events)

## Permissions
This build is **standalone/no-perms**: no ACE permissions are required to use the system.

## Ensure Order
```
ensure oxmysql
ensure PoliceEMSActivity
ensure BigDaddy-Chat
ensure lb-phone           # optional
ensure TwoPoint_EvidenceStandalone
```

## Commands
- /forensic : toggle scanner (LEO + duty required)
- /evidence : open UI (LEO only; analyze/delete requires duty + lab)
- /evidencelist : chat fallback list of bags

### Wiretap commands (optional)
These change your tapped numbers and update the laptop UI live (if open).
- /wiretap add <number> [label]
- /wiretap remove <number>
- /wiretap list

## Keybinds & Controls
- **Collect evidence:** press **E** (default GTA control **38**) while the **Forensic Scanner** is ON and you are within range of evidence.
- **UI interaction:** mouse click to switch tabs / select bags / add/remove wiretaps / analyze / delete (when allowed).
- **Close UI:** press **ESC** (or use the UI close button).

**Change the collect key:** edit `Config.CollectKey` in `config.lua` (default `38` = **E**).

## Config
Edit `config.lua`:
- `Config.Labs` to change lab locations/radius
- `Config.Blips` to show labs to everyone or only LEOs
- Evidence chances/TTLs under `Config.Casings`, `Config.Blood`, `Config.Vehicles`
- Name sync interval under `Config.NameSyncIntervalSeconds`

## Notes on Realism
- Suppressors reduce casing drop chance
- Gloves reduce fingerprint chance (simple drawable-based glove check, configurable)
- Rain washes evidence faster (`Config.RainWashMultiplier`)


## Inspect & Cleanup (Civilians)
This is for **group.member** (or any group you grant the inspect ACE node to). It lets players inspect for **evidence they personally created** and attempt to clean it up.

### Permission
Add this to `server.cfg`:
```
add_ace group.member twopoint.evidence.inspect allow
```

### Commands
- `/inspect` (alias: `/instpect`) — toggle Inspect mode

### Controls (while Inspect mode is ON and near your evidence)
- **E** — Quick Wipe (easy minigame)  
  - If you pass the minigame: **35% chance** to downgrade evidence to **partial**.
- **H** — Thorough Clean (hard minigame)  
  - If you pass the minigame: **50% chance** to fully remove the evidence.
  - If you fail the minigame: **nothing changes** (all evidence stays).

### How “partial evidence” affects cops
Partial evidence is harder to use: it shows a **profile fragment + confidence** instead of full identifying details until more context/evidence is collected.
