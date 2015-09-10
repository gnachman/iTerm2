# Badge Feature Evolution Proposal

---

## 1. Configure Current Mechanism
This step involves keeping the current algorithm for drawing the badge as it is, but exposing all the _magic numbers_ in the **Advanced Preferences**

- [x] Font Name (with a check that it exists, falling back to Helvetica)
- [x] Bold on/off
- [x] Max Size Width (% of current view)
- [x] Max Size Height (% of current view)
- [x] Add VerticalMargin
- [x] Add HorizontalMargin
- [ ] Add setting controlling whether badge label wraps

## 2. Positioning Refinements to Current Algorithm
- [ ] Add static Max Width
- [ ] Add static Max Height
- [ ] Add static Min Width
- [ ] Add static Min Height
- [ ] Choose pin location from (TopLeft, TopRight, TopCenter, MidLeft, BottomRight, BottomCenter, BottomLeft)
	- [ ] **Optional:** enhance iTermAdvancedPreferences to allow settings that select from an enum
	- make margins work as expected with all pin locations

## 3. Style Enhancements
- [ ] consider converting implementation from NSLabel to a virtual terminal pane, that can optionally have a separate profile, then would get all the below for free
- [ ] Add setting for badge background color
- [ ] Add setting for badge outline
	- [ ] width
	- [ ] color
- [ ] Add color parsing
	- [ ] parse terminal escape codes
	- [ ] use badge color as foreground color
	- [ ] use underlying terminal theme for base colors
	- [ ] always understand xterm-256color codes, regardless of underlying terminal
- [ ] Add inline images a la shell integration
