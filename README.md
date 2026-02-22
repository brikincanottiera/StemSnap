# StemSnap
**Drop your stems into the right folder buses automatically: no clicks, no drag.**

![StemSnap GUI](assets/StemSnap%20Gui.png)
![StemSnap Settings](assets/StemSnap%20Settings.png)

StemSnap is a REAPER script that automatically routes your selected tracks into the correct folder buses based on their names. Select your stems, run the script, confirm and done.

---

## Features
- Automatic matching for simple bus names (`Kick Bus`, `Snare Bus`, `Bass Group`)
- Custom rules for compound bus names (`Hi End Perc Bus`, `Riser & Fx Bus`)
- Visual confirmation before routing with color-coded track list
- Partial routing support — skip unrecognized tracks or assign them manually
- Custom rules saved and reused across sessions
- Window position remembered between runs

## Requirements
- REAPER 6+
- [ReaImGui](https://github.com/cfillion/reaimgui) (install via ReaPack)

## Installation

### Via ReaPack (recommended)
1. In REAPER, go to **Extensions → ReaPack → Import repositories**
2. Paste this URL:
```
   https://github.com/brikincanottiera/StemSnap/raw/main/index.xml
```
3. Go to **Extensions → ReaPack → Browse packages**, find **StemSnap** and install it

### Manual
1. Download `StemSnap.lua`
2. Copy it to your REAPER Scripts folder
3. In REAPER, go to **Actions → Load ReaScript** and load the file

## How it works

### Automatic matching
Buses containing `bus` or `group` in their name are detected automatically. The first word is used as a keyword:

| Bus name | Matched keyword |
|---|---|
| Kick Bus | `kick` |
| Snare Bus | `snare` |
| 808 Bus | `808` |
| Bass Group | `bass` |

### Custom rules
Buses with compound names need a custom rule. Open **⚙ Settings** and add:

| Keyword | Bus |
|---|---|
| `hihat` | Hi End Perc Bus |
| `open` | Hi End Perc Bus |
| `riser` | Riser & Fx Bus |

Custom rules are saved permanently and reused every time you run the script.

## Author
**Brik in canottiera**
GitHub: [brikincanottiera](https://github.com/brikincanottiera)

## License
MIT
