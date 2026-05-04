# BetterSituation

BetterSituation is a World of Warcraft Retail addon focused on transmog situation visibility and outfit prediction.

Status: bootstrap implementation.

## Scope in this milestone
- Addon skeleton and slash command bootstrap
- Packaging script for release zip generation
- Git repository setup for public hosting

## Installation (development)
1. Copy this folder into Interface/AddOns.
2. Ensure the in-game addon folder name is BetterSituation.
3. Reload the game UI.

## Slash Commands
- /bs
- /bettersituation
- /bs help
- /bs version

## Build a Release Zip
From this folder run:

powershell
./make-release.ps1

The archive is generated in .build as BetterSituation-v<version>.zip.

## Git Bootstrap
From this folder run:

powershell
git init
git add .
git commit -m "Initial BetterSituation bootstrap"

To connect to GitHub and push:

powershell
gh repo create BetterSituation --public --source . --remote origin --push

## Next Milestone
- Transmog situation criteria tracker
- Hypothetical outfit prediction engine
- Outfit list UI augmentation (tooltip details, summary, candidate highlighting)
