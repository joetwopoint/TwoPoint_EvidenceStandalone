# TwoPoint_EvidenceStandalone

Standalone evidence + forensic system designed for **pe-core** servers using **SQL only** (via `oxmysql`).
No ox_inventory, no ox_target, no ESX/QB.

## Features
- Automatic evidence drops:
  - Shell casings when shooting
  - Blood drops when taking significant damage
  - Fingerprints when entering a vehicle
- Officers can toggle a scanner: `/forensic`
  - Shows nearby evidence markers
  - Press **E** to collect
- Collected evidence goes into SQL “bags” (no items needed)
- Commands:
  - `/evidence` list your collected bags
  - `/evidenceview <BagID>` view basic info
  - `/evidenceanalyze <BagID>` lab-only full analysis (shows fingerprint/DNA + identifier)
  - `/evidencedelete <BagID>` lab-only delete a bag

## Permissions (DiscordAcePerms / ACE)
Give your LEO groups these nodes in server.cfg:

```
add_ace group.LEO twopoint.evidence allow
```

## Duty requirement (PoliceEMSActivity)
By default, the script requires players to be **on duty** (PoliceEMSActivity export `IsOnDuty`).
Toggle in `config.lua`:
- `Config.RequireOnDuty = true/false`

## BigDaddy Chat integration (/chatname)
The script stores each player’s **character_name** in `tp_evidence_profiles`.

It updates names:
1) Immediately when it sees `/chatname <name>` via the `chatMessage` event (best case)
2) Every `Config.NamePollSeconds` seconds by reading `exports['BigDaddy-Chat']:getPlayerName(src)` (fallback)

If your BigDaddy chat does not fire `chatMessage`, the polling still keeps names synced.

## Database
Tables auto-create on resource start:
- `tp_evidence_profiles`
- `tp_evidence_world`
- `tp_evidence_bags`

## Install
1) Ensure dependencies:
   - `ensure oxmysql`
2) Add resource folder:
   - `ensure TwoPoint_EvidenceStandalone`
3) Configure ACE permissions (above).
4) Restart.

## Notes
- World evidence uses `expires_at` in SQL. Each dropped evidence item can pass a per-type TTL (`Config.Realism.TTLByType`) and weather can shorten it (`Config.Realism.RainDecayMultiplier`).
- This is intentionally lightweight and avoids any inventory/target frameworks.

## Lab locations & blips
Labs are configured in `config.lua` in `Config.Labs`.

You can show configurable map blips for everyone (or only LEO) via `Config.Blips`:
- `Enabled`
- `ShowToAll`
- `DefaultSprite`, `DefaultColor`, `Scale`, `ShortRange`
- Optional per-category overrides: `PoliceSprite/Color`, `HospitalSprite/Color`

Per-lab overrides:
- `enabled = false` to disable that lab
- `blipSprite`, `blipColor`, `blipScale`, `blipShortRange`, `blipName`


## Evidence UI
- `/evidence` opens the Evidence Bags UI.
- Top-right pill shows **In Lab** / **Not in Lab** status.
- Analyze/Delete buttons only work while inside one of the configured lab radii.

## Permissions
Add this to your `server.cfg`:
```
add_ace group.LEO twopoint.evidence allow
```
