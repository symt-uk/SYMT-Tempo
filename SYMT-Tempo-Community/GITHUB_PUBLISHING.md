# Publishing guide for maintainers

## Recommended GitHub settings

- **Repository name:** `SYMT-Tempo`
- **Owner:** SYMT Limited GitHub organisation, if available; otherwise the authorised publisher account.
- **Visibility:** Public
- **Description:** `Lightweight Windows task and time tracker with a floating timer, local storage and CSV/JSON export. Free personal-use, source-available Community Edition by SYMT Limited.`
- **Website:** `https://www.symt.co.uk`
- **Topics:** `time-tracker`, `windows`, `productivity`, `powershell`, `winforms`, `portable-app`, `csv-export`, `community-edition`, `source-available`
- **Issues:** On; **Discussions:** Optional; **Wiki:** Off initially.
- **GitHub licence chooser:** Do NOT select MIT, GPL or other standard open-source licence. Keep the bundled custom `LICENSE.txt`.

## Upload (important)

1. Create an **empty** public GitHub repository (do not initialise with README/licence/gitignore).
2. **Extract the ZIP**. Open `SYMT-Tempo-Community` and upload the **contents** into the repo. GitHub web upload may not preserve empty directories, and browser drag/drop can behave differently with nested directories. For reliable full-folder uploads, use Git CLI or GitHub Desktop (recommended).
3. Confirm `.github`, `Assets`, `Build`, `Lib`, `tests`, `Tempo.ps1`, `README.md`, `LICENSE.txt` are present. Do not upload your own `Data` directory.
4. Before enabling Releases, read the custom licence and secure third-party rights/legal review. Check the app on Windows.
5. Publish `v0.5.1` tag and upload the official portable ZIP and installer EXE as **release attachments** only when tested. Do not commit installers into the source branch.

## Repository branding
Use name **SYMT Tempo** and a neutral independent clock icon for social preview / repository avatar. Keep the supplied corporate logo inside official application assets and the About screen; trademark rights remain reserved. Do not imply that GitHub public visibility grants a logo licence.

## Publish by GitHub Desktop instead of web drag/drop
Clone new repository, copy the extracted files into its clone, review changed files, commit as `Initial Community Edition v0.5.1`, then push.
