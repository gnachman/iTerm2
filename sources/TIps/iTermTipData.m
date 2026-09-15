//
//  iTermTipData.m
//  iTerm2
//
//  Created by George Nachman on 6/19/15.
//
//

#import "iTermTipData.h"
#import "iTermTip.h"

@implementation iTermTipData

+ (NSDictionary *)allTips {
  // The keys in this dictionary are saved in user defaults and should not be changed or
  // recycled, or users will see the same tip more than once.
  return @{
    // Big new features
            @"000": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.000.Title", nil, [NSBundle mainBundle], @"Tip of the Day", @"Tip of the day title, id 000"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.000.Body", nil, [NSBundle mainBundle], @"This window shows the iTerm2 tip of the day. It’ll appear every 24 hours to let you know about new features and hidden secrets. Hit “More Options” to view more tips or to stop getting them altogether.", @"Tip of the day body, id 000") },
            @"0000": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0000.Title", nil, [NSBundle mainBundle], @"Shell Integration", @"Tip of the day title, id 0000"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0000.Body", nil, [NSBundle mainBundle], @"The big new feature of iTerm2 version 3 is Shell Integration. Click “Learn More” for all the details.", @"Tip of the day body, id 0000"),
                          kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0001": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0001.Title", nil, [NSBundle mainBundle], @"Timestamps", @"Tip of the day title, id 0001"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0001.Body", nil, [NSBundle mainBundle], @"“View > Show Timestamps” shows the time (and date, if appropriate) when each line was last modified.", @"Tip of the day body, id 0001") },

            @"0002": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0002.Title", nil, [NSBundle mainBundle], @"Password Manager", @"Tip of the day title, id 0002"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0002.Body", nil, [NSBundle mainBundle], @"Did you know iTerm2 has a password manager? Open it with “Window > Password Manager.” You can define a Trigger to open it for you at a password prompt in “Settings > Profiles > Advanced > Triggers.”", @"Tip of the day body, id 0002") },
            @"0003": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0003.Title", nil, [NSBundle mainBundle], @"Open Quickly", @"Tip of the day title, id 0003"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0003.Body", nil, [NSBundle mainBundle], @"You can quickly search through your sessions with “View > Open Quickly” (⇧⌘O). You can type a query and sessions whose name, badge, current hostname, current user name, recent commands, and recent working directories match will be surfaced. It works best with Shell Integration so the user name, hostname, command, and directories can be known even while sshed.", @"Tip of the day body, id 0003"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0004": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0004.Title", nil, [NSBundle mainBundle], @"Undo Close", @"Tip of the day title, id 0004"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0004.Body", nil, [NSBundle mainBundle], @"If you close a session, tab, or window by accident you can undo it with “Edit > Undo” (⌘Z). By default you have five seconds to undo, but you can adjust that timeout in “Settings > Profiles > Session.”", @"Tip of the day body, id 0004") },

            @"0005": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0005.Title", nil, [NSBundle mainBundle], @"Annotations", @"Tip of the day title, id 0005"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0005.Body", nil, [NSBundle mainBundle], @"Want to mark up your scrollback history? Right click on a selection and choose “Annotate Selection” to add a personal note to it. Use “View > Show Annotations” to show or hide them, and look in “Edit > Marks and Annotations” for more things you can do.", @"Tip of the day body, id 0005") },

            @"0006": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0006.Title", nil, [NSBundle mainBundle], @"Copy with Styles", @"Tip of the day title, id 0006"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0006.Body", nil, [NSBundle mainBundle], @"Copy a selection with ⌥⌘C to include styles such as colors and fonts. You can make this the default action for Copy in “Settings > Advanced.”", @"Tip of the day body, id 0006") },
            @"0007": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0007.Title", nil, [NSBundle mainBundle], @"Inline Images", @"Tip of the day title, id 0007"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0007.Body", nil, [NSBundle mainBundle], @"iTerm2 can display images (even animated GIFs) inline.", @"Tip of the day body, id 0007"),
                        kTipUrlKey: @"https://iterm2.com/images.html" },

            @"0008": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0008.Title", nil, [NSBundle mainBundle], @"Automatic Profile Switching", @"Tip of the day title, id 0008"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0008.Body", nil, [NSBundle mainBundle], @"Automatic Profile Switching changes the current profile when the username, hostname, or directory changes. Set it up in “Settings > Profiles > Advanced.” It requires Shell Integration to be installed.", @"Tip of the day body, id 0008"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0009": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0009.Title", nil, [NSBundle mainBundle], @"Captured Output", @"Tip of the day title, id 0009"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0009.Body", nil, [NSBundle mainBundle], @"iTerm2 can act like an IDE using the Captured Output feature. When it sees text matching a regular expression you define, like compiler errors, it shows the matching lines in the Toolbelt. You can click to jump to the line in your terminal and double-click to perform an action like opening an editor to the line with the error.", @"Tip of the day body, id 0009"),
                        kTipUrlKey: @"https://iterm2.com/captured_output.html" },

            @"0010": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0010.Title", nil, [NSBundle mainBundle], @"Badges", @"Tip of the day title, id 0010"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0010.Body", nil, [NSBundle mainBundle], @"You can display a status message in the top right of your session in the background. It’s called a “Badge.” If you install Shell Integration you can include info like user name, hostname, current directory, and more.", @"Tip of the day body, id 0010"),
                        kTipUrlKey: @"https://iterm2.com/badges.html" },

            @"0011" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0011.Title", nil, [NSBundle mainBundle], @"Dynamic Profiles", @"Tip of the day title, id 0011"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0011.Body", nil, [NSBundle mainBundle], @"Dynamic Profiles let you store your profiles as one or more JSON files. It’s great for batch creating and editing profiles.", @"Tip of the day body, id 0011"),
                         kTipUrlKey: @"https://iterm2.com/dynamic-profiles.html" },

            @"0012" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0012.Title", nil, [NSBundle mainBundle], @"Advanced Paste", @"Tip of the day title, id 0012"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0012.Body", nil, [NSBundle mainBundle], @"“Edit > Paste Special > Advanced Paste” lets you preview and edit text before you paste. You get to tweak options, like how to handle control codes, or even to base-64 encode before pasting.", @"Tip of the day body, id 0012") },

            @"0013" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0013.Title", nil, [NSBundle mainBundle], @"Zoom", @"Tip of the day title, id 0013"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0013.Body", nil, [NSBundle mainBundle], @"Ever wanted to focus on a block of lines without distraction, or limit Find to a single command’s output? Select the lines and choose “View > Zoom In on Selection.” The session’s contents will be temporarily replaced with the selection. Press “esc” to unzoom.", @"Tip of the day body, id 0013") },

    // Big but not new features
            @"0014": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0014.Title", nil, [NSBundle mainBundle], @"Semantic History", @"Tip of the day title, id 0014"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0014.Body", nil, [NSBundle mainBundle], @"The “Semantic History” feature allows you to ⌘-click on a file or URL to open it.", @"Tip of the day body, id 0014"), },

            @"0015": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0015.Title", nil, [NSBundle mainBundle], @"Tmux Integration", @"Tip of the day title, id 0015"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0015.Body", nil, [NSBundle mainBundle], @"If you use tmux, try running “tmux -CC” to get iTerm2’s tmux integration mode. The tmux windows show up as native iTerm2 windows, and you can use iTerm2’s keyboard shortcuts. It even works over ssh!", @"Tip of the day body, id 0015"),
                        kTipUrlKey: @"https://gitlab.com/gnachman/iterm2/wikis/TmuxIntegration" },

            @"0016": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0016.Title", nil, [NSBundle mainBundle], @"Triggers", @"Tip of the day title, id 0016"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0016.Body", nil, [NSBundle mainBundle], @"iTerm2 can automatically perform actions you define when text matching a regular expression is received. For example, you can highlight text or show an alert box. Set it up in “Settings > Profiles > Advanced > Triggers.”", @"Tip of the day body, id 0016"),
                        kTipUrlKey: @"https://www.iterm2.com/documentation-triggers.html" },

            @"0017": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0017.Title", nil, [NSBundle mainBundle], @"Smart Selection", @"Tip of the day title, id 0017"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0017.Body", nil, [NSBundle mainBundle], @"Quadruple click to perform Smart Selection. It figures out if you’re selecting a URL, filename, email address, etc. based on prioritized regular expressions.", @"Tip of the day body, id 0017"),
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0018": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0018.Title", nil, [NSBundle mainBundle], @"Instant Replay", @"Tip of the day title, id 0018"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0018.Body", nil, [NSBundle mainBundle], @"Press ⌥⌘B to step back in time in a terminal window. Use arrow keys to go frame by frame. Hold ⇧ and press arrow keys to go faster.", @"Tip of the day body, id 0018") },

            @"0019": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0019.Title", nil, [NSBundle mainBundle], @"Hotkey Window", @"Tip of the day title, id 0019"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0019.Body", nil, [NSBundle mainBundle], @"You can have a terminal window open with a keystroke, even while in other apps. Click “Create a Dedicated Hotkey Window” in “Settings > Keys.”", @"Tip of the day body, id 0019") },

    // Small things
            @"0020": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0020.Title", nil, [NSBundle mainBundle], @"Hotkey Window", @"Tip of the day title, id 0020"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0020.Body", nil, [NSBundle mainBundle], @"Hotkey windows can stay open after losing focus. Turn it on in “Window > Pin Hotkey Window.”", @"Tip of the day body, id 0020") },

            @"0021": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0021.Title", nil, [NSBundle mainBundle], @"Cursor Guide", @"Tip of the day title, id 0021"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0021.Body", nil, [NSBundle mainBundle], @"The cursor guide is a horizontal line that follows your cursor. You can turn it on in “Settings > Profiles > Colors” or toggle it with the ⌥⌘; shortcut.", @"Tip of the day body, id 0021") },  // TODO Add learn more for escape sequence

            @"0022": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0022.Title", nil, [NSBundle mainBundle], @"Shell Integration: Alerts", @"Tip of the day title, id 0022"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0022.Body", nil, [NSBundle mainBundle], @"The Shell Integration feature lets you ask to be alerted (⌥⌘A) when a long-running command completes.", @"Tip of the day body, id 0022"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0023": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0023.Title", nil, [NSBundle mainBundle], @"Cursor Blink Rate", @"Tip of the day title, id 0023"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0023.Body", nil, [NSBundle mainBundle], @"You can configure how quickly the cursor blinks in “Settings > Advanced.”", @"Tip of the day body, id 0023") },

            @"0024": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0024.Title", nil, [NSBundle mainBundle], @"Shell Integration: Navigation", @"Tip of the day title, id 0024"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0024.Body", nil, [NSBundle mainBundle], @"The Shell Integration feature lets you navigate among shell prompts with ⇧⌘↑ and ⇧⌘↓.", @"Tip of the day body, id 0024"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0025": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0025.Title", nil, [NSBundle mainBundle], @"Shell Integration: Status", @"Tip of the day title, id 0025"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0025.Body", nil, [NSBundle mainBundle], @"The Shell Integration feature puts a blue arrow next to your shell prompt. If you run a command that fails, it turns red. Right click on it to get the running time and status.", @"Tip of the day body, id 0025"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0026": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0026.Title", nil, [NSBundle mainBundle], @"Shell Integration: Selection", @"Tip of the day title, id 0026"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0026.Body", nil, [NSBundle mainBundle], @"With Shell Integration installed, you can select the output of the last command with ⇧⌘A.", @"Tip of the day body, id 0026"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0027": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0027.Title", nil, [NSBundle mainBundle], @"Bells", @"Tip of the day title, id 0027"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0027.Body", nil, [NSBundle mainBundle], @"The dock icon shows a count of the number of bells rung and notifications posted since the app was last active.", @"Tip of the day body, id 0027") },

            @"0028": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0028.Title", nil, [NSBundle mainBundle], @"Shell Integration: Downloads", @"Tip of the day title, id 0028"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0028.Body", nil, [NSBundle mainBundle], @"If you install Shell Integration on a machine you ssh to, you can right click on a filename (for example, in the output of “ls”) and choose “Download with scp” to download the file.", @"Tip of the day body, id 0028"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0029": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0029.Title", nil, [NSBundle mainBundle], @"Find Your Cursor", @"Tip of the day title, id 0029"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0029.Body", nil, [NSBundle mainBundle], @"Press ⌘/ to locate your cursor. It’s fun!", @"Tip of the day body, id 0029") },

            @"0030": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0030.Title", nil, [NSBundle mainBundle], @"Customize Smart Selection", @"Tip of the day title, id 0030"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0030.Body", nil, [NSBundle mainBundle], @"You can edit Smart Selection regular expressions in “Settings > Profiles > Advanced > Smart Selection.”", @"Tip of the day body, id 0030"),
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0031": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0031.Title", nil, [NSBundle mainBundle], @"Smart Selection Actions", @"Tip of the day title, id 0031"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0031.Body", nil, [NSBundle mainBundle], @"Assign an action to a Smart Selection rule in “Settings > Profiles > Advanced > Smart Selection > Edit Actions.” They go in the context menu and override semantic history on ⌘-click.", @"Tip of the day body, id 0031"),
                        kTipUrlKey: @"https://www.iterm2.com/smartselection.html" },

            @"0032": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0032.Title", nil, [NSBundle mainBundle], @"Visual Bell", @"Tip of the day title, id 0032"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0032.Body", nil, [NSBundle mainBundle], @"If you want the visual bell to flash the whole screen instead of show a bell icon, you can turn that on in “Settings > Advanced.”", @"Tip of the day body, id 0032") },

            @"0033": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0033.Title", nil, [NSBundle mainBundle], @"Tab Menu", @"Tip of the day title, id 0033"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0033.Body", nil, [NSBundle mainBundle], @"Right click on a tab to change its color, close tabs after it, or to close all other tabs.", @"Tip of the day body, id 0033") },

            @"0034": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0034.Title", nil, [NSBundle mainBundle], @"Tags", @"Tip of the day title, id 0034"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0034.Body", nil, [NSBundle mainBundle], @"You can assign tags to your profiles, and by clicking “Tags>” anywhere you see a list of profiles you can browse those tags.", @"Tip of the day body, id 0034") },

            @"0035": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0035.Title", nil, [NSBundle mainBundle], @"Tag Hierarchy", @"Tip of the day title, id 0035"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0035.Body", nil, [NSBundle mainBundle], @"If you put a slash in a profile’s tag, that implicitly defines a hierarchy. You can see it in the Profiles menu as nested submenus.", @"Tip of the day body, id 0035") },

            @"0036": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0036.Title", nil, [NSBundle mainBundle], @"Downloads", @"Tip of the day title, id 0036"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0036.Body", nil, [NSBundle mainBundle], @"iTerm2 can download files by base-64 encoding them. Click “Learn More” to download a shell script that makes it easy.", @"Tip of the day body, id 0036"),
                        kTipUrlKey: @"https://iterm2.com/download.sh" },

            @"0037": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0037.Title", nil, [NSBundle mainBundle], @"Command Completion", @"Tip of the day title, id 0037"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0037.Body", nil, [NSBundle mainBundle], @"If you install Shell Integration, ⇧⌘; helps you complete commands. It remembers the commands you’ve run on each host that has Shell Integration installed. It knows how often that command was run and how recently to help make the best suggestions.", @"Tip of the day body, id 0037"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0038": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0038.Title", nil, [NSBundle mainBundle], @"Recent Directories", @"Tip of the day title, id 0038"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0038.Body", nil, [NSBundle mainBundle], @"iTerm2 remembers which directories you use the most on each host that has Shell Integration installed. There’s a Toolbelt tool to browse them, and ⌥⌘/ gives you a popup sorted by frequency and recency of use.", @"Tip of the day body, id 0038"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0039": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0039.Title", nil, [NSBundle mainBundle], @"Favorite Directories", @"Tip of the day title, id 0039"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0039.Body", nil, [NSBundle mainBundle], @"If you have Shell Integration installed, you can “star” a directory to keep it always at the bottom of the Recent Directories tool in the Toolbelt. Right click and choose “Toggle Star.”", @"Tip of the day body, id 0039"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0040": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0040.Title", nil, [NSBundle mainBundle], @"Shell Integration History", @"Tip of the day title, id 0040"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0040.Body", nil, [NSBundle mainBundle], @"Install Shell Integration and turn on “Settings > General > Save copy/paste and command history to disk” to remember command history per host across restarts of iTerm2.", @"Tip of the day body, id 0040"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0041": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0041.Title", nil, [NSBundle mainBundle], @"Paste File as Base64", @"Tip of the day title, id 0041"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0041.Body", nil, [NSBundle mainBundle], @"Copy a file to the pasteboard in Finder and then use “Edit > Paste Special > Paste File Base64-Encoded” for easy uploads of binary files. Use ”base64 -D” (or -d on Linux) on the remote host to decode it.", @"Tip of the day body, id 0041") },

            @"0042": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0042.Title", nil, [NSBundle mainBundle], @"Split Panes", @"Tip of the day title, id 0042"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0042.Body", nil, [NSBundle mainBundle], @"You can split a tab into multiple panes with ⌘D and ⇧⌘D.", @"Tip of the day body, id 0042") },

            @"0043": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0043.Title", nil, [NSBundle mainBundle], @"Adjust Split Panes", @"Tip of the day title, id 0043"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0043.Body", nil, [NSBundle mainBundle], @"Resize split panes with the keyboard using ^⌘-Arrow Key.", @"Tip of the day body, id 0043") },

            @"0044": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0044.Title", nil, [NSBundle mainBundle], @"Move Cursor", @"Tip of the day title, id 0044"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0044.Body", nil, [NSBundle mainBundle], @"Hold ⌥ and click to move your cursor. It works best with Shell Integration installed (to avoid sending up/down arrow keys to your shell).", @"Tip of the day body, id 0044"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0045": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0045.Title", nil, [NSBundle mainBundle], @"Edge Windows", @"Tip of the day title, id 0045"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0045.Body", nil, [NSBundle mainBundle], @"You can tell your profile to create windows that are attached to one edge of the screen in “Settings > Profiles > Window.” You can resize them by dragging the edges.", @"Tip of the day body, id 0045") },

            @"0046": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0046.Title", nil, [NSBundle mainBundle], @"Tab Color", @"Tip of the day title, id 0046"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0046.Body", nil, [NSBundle mainBundle], @"You can assign colors to tabs in “Settings > Profiles > Colors,” or in the View menu.", @"Tip of the day body, id 0046") },

            @"0047": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0047.Title", nil, [NSBundle mainBundle], @"Rectangular Selection", @"Tip of the day title, id 0047"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0047.Body", nil, [NSBundle mainBundle], @"Hold ⌥⌘ while dragging to make a rectangular selection.", @"Tip of the day body, id 0047") },

            @"0048": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0048.Title", nil, [NSBundle mainBundle], @"Multiple Selection", @"Tip of the day title, id 0048"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0048.Body", nil, [NSBundle mainBundle], @"Hold ⌘ while dragging to make multiple discontinuous selections.", @"Tip of the day body, id 0048") },

            @"0049": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0049.Title", nil, [NSBundle mainBundle], @"Dragging Panes", @"Tip of the day title, id 0049"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0049.Body", nil, [NSBundle mainBundle], @"Hold ⇧⌥⌘ and drag a session into another session to create or change split panes.", @"Tip of the day body, id 0049") },

            @"0050": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0050.Title", nil, [NSBundle mainBundle], @"Cursor Boost", @"Tip of the day title, id 0050"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0050.Body", nil, [NSBundle mainBundle], @"Adjust Cursor Boost in “Settings > Profiles > Colors” to make all colors more muted, except the cursor. Use a bright white cursor and it pops!", @"Tip of the day body, id 0050") },

            @"0051": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0051.Title", nil, [NSBundle mainBundle], @"Minimum Contrast", @"Tip of the day title, id 0051"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0051.Body", nil, [NSBundle mainBundle], @"Adjust “Minimum Contrast” in “Settings > Profiles > Colors” to ensure text is always legible regardless of text/background color combination.", @"Tip of the day body, id 0051") },

            @"0052": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0052.Title", nil, [NSBundle mainBundle], @"Tabs", @"Tip of the day title, id 0052"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0052.Body", nil, [NSBundle mainBundle], @"Normally, new tabs appear at the end of the tab bar. There’s a setting in “Settings > Advanced” to place them next to your current tab.", @"Tip of the day body, id 0052") },

            @"0053": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0053.Title", nil, [NSBundle mainBundle], @"Base Conversion", @"Tip of the day title, id 0053"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0053.Body", nil, [NSBundle mainBundle], @"Right-click on a number and the context menu shows it converted to hex or decimal as appropriate.", @"Tip of the day body, id 0053") },

            @"0054": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0054.Title", nil, [NSBundle mainBundle], @"Saved Searches", @"Tip of the day title, id 0054"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0054.Body", nil, [NSBundle mainBundle], @"In “Settings > Keys” you can assign a keystroke to a search for a regular expression with the “Find Regular Expression…” action.", @"Tip of the day body, id 0054") },

            @"0055": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0055.Title", nil, [NSBundle mainBundle], @"Find URLs", @"Tip of the day title, id 0055"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0055.Body", nil, [NSBundle mainBundle], @"Search for URLs using “Edit > Find > Find URLs.” Navigate search results with ⌘G and ⇧⌘G. Open the current selection with ⌥⌘O.", @"Tip of the day body, id 0055") },

            @"0056": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0056.Title", nil, [NSBundle mainBundle], @"Triggers", @"Tip of the day title, id 0056"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0056.Body", nil, [NSBundle mainBundle], @"The “instant” checkbox in a Trigger allows it to fire while the cursor is on the same line as the text that matches your regular expression.", @"Tip of the day body, id 0056") },
            @"0057": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0057.Title", nil, [NSBundle mainBundle], @"Soft Boundaries", @"Tip of the day title, id 0057"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0057.Body", nil, [NSBundle mainBundle], @"Turn on “Edit > Selection Respects Soft Boundaries” to recognize split pane dividers in programs like vi, emacs, and tmux so you can select multiple lines of text.", @"Tip of the day body, id 0057") },

            @"0058": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0058.Title", nil, [NSBundle mainBundle], @"Select Without Dragging", @"Tip of the day title, id 0058"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0058.Body", nil, [NSBundle mainBundle], @"Single click where you want to start a selection and ⇧-click where you want it to end to select text without dragging.", @"Tip of the day body, id 0058") },

            @"0059" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0059.Title", nil, [NSBundle mainBundle], @"Smooth Window Resizing", @"Tip of the day title, id 0059"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0059.Body", nil, [NSBundle mainBundle], @"Hold ^ while resizing a window and it won’t snap to the character grid: you can make it any size you want.", @"Tip of the day body, id 0059") },

            @"0060" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0060.Title", nil, [NSBundle mainBundle], @"Pasting Tabs", @"Tip of the day title, id 0060"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0060.Body", nil, [NSBundle mainBundle], @"If you paste text containing tabs, you’ll be asked if you want to convert them to spaces. It’s handy at the shell prompt to avoid triggering filename completion.", @"Tip of the day body, id 0060") },

            @"0061" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0061.Title", nil, [NSBundle mainBundle], @"Bell Silencing", @"Tip of the day title, id 0061"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0061.Body", nil, [NSBundle mainBundle], @"Did you know? If the bell rings too often, you’ll be asked if you’d like to silence it temporarily. iTerm2 cares about your comfort.", @"Tip of the day body, id 0061") },

            @"0062" : @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0062.Title", nil, [NSBundle mainBundle], @"Profile Search", @"Tip of the day title, id 0062"),
                         kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0062.Body", nil, [NSBundle mainBundle], @"Every list of profiles has a search field (e.g., in ”Settings > Profiles.”) You can use various operators to restrict your search query. Click “Learn More” for all the details.", @"Tip of the day body, id 0062"),
                         kTipUrlKey: @"https://iterm2.com/search_syntax.html" },

            @"0063": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0063.Title", nil, [NSBundle mainBundle], @"Color Schemes", @"Tip of the day title, id 0063"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0063.Body", nil, [NSBundle mainBundle], @"The online color gallery features over one hundred beautiful color schemes you can download.", @"Tip of the day body, id 0063"),
                        kTipUrlKey: @"https://www.iterm2.com/colorgallery"},

            @"0064": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0064.Title", nil, [NSBundle mainBundle], @"ASCII/Non-Ascii Fonts", @"Tip of the day title, id 0064"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0064.Body", nil, [NSBundle mainBundle], @"You can have a separate font for ASCII versus non-ASCII text. Enable it in “Settings > Profiles > Text.”", @"Tip of the day body, id 0064") },

            @"0065": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0065.Title", nil, [NSBundle mainBundle], @"Coprocesses", @"Tip of the day title, id 0065"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0065.Body", nil, [NSBundle mainBundle], @"A coprocess is a job, such as a shell script, that has a special relationship with a particular iTerm2 session. All output in a terminal window (that is, what you see on the screen) is also input to the coprocess. All output from the coprocess acts like text that the user is typing at the keyboard.", @"Tip of the day body, id 0065"),
                        kTipUrlKey: @"https://iterm2.com/coprocesses.html" },

            @"0066": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0066.Title", nil, [NSBundle mainBundle], @"Touch Bar Customization", @"Tip of the day title, id 0066"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0066.Body", nil, [NSBundle mainBundle], @"You can customize the touch bar by selecting “View > Customize Touch Bar.” You can add a tab bar for full-screen mode, a user-customizable status button, and you can even define your own touch bar buttons in Settings > Keys. There’s also a new shell integration tool to customize touch bar function key labels.", @"Tip of the day body, id 0066") },

            @"0067": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0067.Title", nil, [NSBundle mainBundle], @"Ligatures", @"Tip of the day title, id 0067"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0067.Body", nil, [NSBundle mainBundle], @"If you use a font that supports ligatures, you can enable ligature support in Settings > Profiles > Text.", @"Tip of the day body, id 0067") },

            @"0068": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0068.Title", nil, [NSBundle mainBundle], @"Floating Hotkey Window", @"Tip of the day title, id 0068"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0068.Body", nil, [NSBundle mainBundle], @"New in 3.1: You can configure your hotkey window to appear over other apps’ full screen windows. Turn on “Floating Window” in “Settings > Profiles > Keys > Customize Hotkey Window.”", @"Tip of the day body, id 0068") },

            @"0069": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0069.Title", nil, [NSBundle mainBundle], @"Multiple Hotkey Windows", @"Tip of the day title, id 0069"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0069.Body", nil, [NSBundle mainBundle], @"New in 3.1: You can have multiple hotkey windows. Each profile can have one or more hotkeys.", @"Tip of the day body, id 0069") },

            @"0070": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0070.Title", nil, [NSBundle mainBundle], @"Double-Tap Hotkey", @"Tip of the day title, id 0070"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0070.Body", nil, [NSBundle mainBundle], @"New in 3.1: You can configure a hotkey window to open on double-tap of a modifier in “Settings > Profiles > Keys > Customize Hotkey Window.”", @"Tip of the day body, id 0070") },

            @"0071": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0071.Title", nil, [NSBundle mainBundle], @"Buried Sessions", @"Tip of the day title, id 0071"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0071.Body", nil, [NSBundle mainBundle], @"You can “bury” a session with “Session > Bury Session.” It remains hidden until you restore it by selecting it from “Session > Buried Sessions > Your session.”", @"Tip of the day body, id 0071") },

            @"0072": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0072.Title", nil, [NSBundle mainBundle], @"Python API", @"Tip of the day title, id 0072"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0072.Body", nil, [NSBundle mainBundle], @"You can add custom behavior to iTerm2 using the Python API.", @"Tip of the day body, id 0072"),
                        kTipUrlKey: @"https://iterm2.com/python-api" },

            @"0073": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0073.Title", nil, [NSBundle mainBundle], @"Status Bar", @"Tip of the day title, id 0073"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0073.Body", nil, [NSBundle mainBundle], @"You can add a configurable status bar to your terminal windows.", @"Tip of the day body, id 0073"),
                        kTipUrlKey: @"https://iterm2.com/3.3/documentation-status-bar.html" },

            @"0074": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0074.Title", nil, [NSBundle mainBundle], @"Minimal Theme", @"Tip of the day title, id 0074"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0074.Body", nil, [NSBundle mainBundle], @"Try the “Minimal” and “Compact” themes to reduce visual clutter. You can set it in “Settings > Appearance > General.”", @"Tip of the day body, id 0074") },

            @"0076": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0076.Title", nil, [NSBundle mainBundle], @"Session Titles", @"Tip of the day title, id 0076"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0076.Body", nil, [NSBundle mainBundle], @"You can configure which elements are present in session titles in “Settings > Profiles > General > Title.”", @"Tip of the day body, id 0076") },

            @"0077": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0077.Title", nil, [NSBundle mainBundle], @"Tab Icons", @"Tip of the day title, id 0077"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0077.Body", nil, [NSBundle mainBundle], @"Tabs can show an icon indicating the current application. Configure it in “Settings > Profiles > General > Icon.”", @"Tip of the day body, id 0077") },

            @"0078": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0078.Title", nil, [NSBundle mainBundle], @"Drag Window by Tab", @"Tip of the day title, id 0078"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0078.Body", nil, [NSBundle mainBundle], @"Hold ⌥ while dragging a tab to move the window. This is useful in the Compact and Minimal themes, which have a very small area for dragging the window.", @"Tip of the day body, id 0078") },

            @"0079": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0079.Title", nil, [NSBundle mainBundle], @"Composer", @"Tip of the day title, id 0079"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0079.Body", nil, [NSBundle mainBundle], @"Press ⇧⌘. to open the Composer. It gives you a scratchpad to edit a command before sending it to the shell.", @"Tip of the day body, id 0079") },

            @"0080": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0080.Title", nil, [NSBundle mainBundle], @"Shell Integration: Uploads", @"Tip of the day title, id 0080"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0080.Body", nil, [NSBundle mainBundle], @"If you install Shell Integration on a machine you ssh to, you can drag-drop from Finder into the remote host by holding ⌥ while dragging. The destination directory is determined by where you drop the file in the terminal window: run cd foo, then drop the file below the cd command, and the file will go into the foo directory.", @"Tip of the day body, id 0080"),
                        kTipUrlKey: @"https://iterm2.com/shell_integration.html" },

            @"0081": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0081.Title", nil, [NSBundle mainBundle], @"Composer Power Features", @"Tip of the day title, id 0081"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0081.Body", nil, [NSBundle mainBundle], @"The composer supports multiple cursors. It also has the ability to send just one command out of a list, making it easy to walk through a list of commands one-by-one. Click the help button in the composer for details.", @"Tip of the day body, id 0081") },

            @"0082": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0082.Title", nil, [NSBundle mainBundle], @"Render Selection", @"Tip of the day title, id 0082"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0082.Body", nil, [NSBundle mainBundle], @"Transform selected text into a prettified, syntax-highlighted view with the “Render Selection” command, ideal for JSON, Markdown, or source code. This feature includes horizontal scrolling for easy log navigation.", @"Tip of the day body, id 0082") },

            @"0083": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0083.Title", nil, [NSBundle mainBundle], @"SSH Integration", @"Tip of the day title, id 0083"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0083.Body", nil, [NSBundle mainBundle], @"Export environment variables and copy files to remote hosts seamlessly with SSH integration. Either configure a profile to use ssh or use it2ssh in place of ssh.", @"Tip of the day body, id 0083") },

            @"0084": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0084.Title", nil, [NSBundle mainBundle], @"Auto Composer", @"Tip of the day title, id 0084"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0084.Body", nil, [NSBundle mainBundle], @"Improve your command line with the “auto composer”, which replaces the command line with a native control for ease of use. Requires shell integration.", @"Tip of the day body, id 0084") },

            @"0085": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0085.Title", nil, [NSBundle mainBundle], @"AI Command Writing", @"Tip of the day title, id 0085"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0085.Body", nil, [NSBundle mainBundle], @"Generate commands using AI by entering a prompt in the composer and selecting “Edit > Engage Artificial Intelligence”. An OpenAI API key is required for this functionality.", @"Tip of the day body, id 0085") },

            @"0086": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0086.Title", nil, [NSBundle mainBundle], @"Codecierge Tool", @"Tip of the day title, id 0086"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0086.Body", nil, [NSBundle mainBundle], @"Set and achieve terminal goals with “Codecierge”, a Toolbelt feature that guides you step-by-step based on your terminal activity. An OpenAI API key is necessary for this feature.", @"Tip of the day body, id 0086") },

            @"0087": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0087.Title", nil, [NSBundle mainBundle], @"Named Marks", @"Tip of the day title, id 0087"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0087.Body", nil, [NSBundle mainBundle], @"Navigate your command history effortlessly with “named marks” by assigning names to lines in the terminal.", @"Tip of the day body, id 0087") },

            @"0088": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0088.Title", nil, [NSBundle mainBundle], @"Font Assignments", @"Tip of the day title, id 0088"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0088.Body", nil, [NSBundle mainBundle], @"You can assign specific fonts to Unicode ranges. Use 'Settings > Profiles > Text > Manage Special Exceptions' to manage it and to install a huge set of Powerline symbols.", @"Tip of the day body, id 0088") },

            @"0089": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0089.Title", nil, [NSBundle mainBundle], @"Disable Transparency", @"Tip of the day title, id 0089"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0089.Body", nil, [NSBundle mainBundle], @"Maintain clarity in your active window while enjoying transparency in background windows by using 'View > Disable transparency in key window'.", @"Tip of the day body, id 0089") },

            @"0090": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0090.Title", nil, [NSBundle mainBundle], @"Leader Shortcut", @"Tip of the day title, id 0090"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0090.Body", nil, [NSBundle mainBundle], @"Create two-keystroke shortcuts with a “leader”: a special keystroke that precedes a custom key binding.", @"Tip of the day body, id 0090") },

            @"0091": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0091.Title", nil, [NSBundle mainBundle], @"Sequence Binding", @"Tip of the day title, id 0091"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0091.Body", nil, [NSBundle mainBundle], @"Execute a series of actions in order with a single shortcut using “sequence” key bindings.", @"Tip of the day body, id 0091") },

            @"0092": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0092.Title", nil, [NSBundle mainBundle], @"Export/Import Settings", @"Tip of the day title, id 0092"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0092.Body", nil, [NSBundle mainBundle], @"Easily backup or transfer your iTerm2 settings using the Export/Import feature in “Settings > General > Settings”.", @"Tip of the day body, id 0092") },

            @"0093": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0093.Title", nil, [NSBundle mainBundle], @"Multi-Session Bindings", @"Tip of the day title, id 0093"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0093.Body", nil, [NSBundle mainBundle], @"Apply key bindings uniformly across multiple sessions for consistent control in different tabs or windows.", @"Tip of the day body, id 0093") },

            @"0094": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0094.Title", nil, [NSBundle mainBundle], @"Inject Trigger", @"Tip of the day title, id 0094"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0094.Body", nil, [NSBundle mainBundle], @"Simulate terminal input as if it were output from a running app with the “Inject” trigger.", @"Tip of the day body, id 0094") },

            @"0095": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0095.Title", nil, [NSBundle mainBundle], @"Trigger Status Bar", @"Tip of the day title, id 0095"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0095.Body", nil, [NSBundle mainBundle], @"Easily manage your triggers using the new Triggers status bar component.", @"Tip of the day body, id 0095") },

            @"0096": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0096.Title", nil, [NSBundle mainBundle], @"Session Size in Tab", @"Tip of the day title, id 0096"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0096.Body", nil, [NSBundle mainBundle], @"Display session size directly in tab titles for convenient at-a-glance information.", @"Tip of the day body, id 0096") },

            @"0097": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0097.Title", nil, [NSBundle mainBundle], @"Advanced Snippet Editing", @"Tip of the day title, id 0097"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0097.Body", nil, [NSBundle mainBundle], @"Edit snippets in Advanced Paste by holding the ⌥ key, or open them in the composer with ⇧.", @"Tip of the day body, id 0097") },

            @"0098": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0098.Title", nil, [NSBundle mainBundle], @"HTML Logs", @"Tip of the day title, id 0098"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0098.Body", nil, [NSBundle mainBundle], @"Save your terminal logs in HTML format for enhanced readability and sharing capabilities.", @"Tip of the day body, id 0098") },

            @"0099": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0099.Title", nil, [NSBundle mainBundle], @"ASCIICast Logs", @"Tip of the day title, id 0099"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0099.Body", nil, [NSBundle mainBundle], @"Create and play back terminal recordings with ASCIICast logs, compatible with asciinema.", @"Tip of the day body, id 0099") },

            @"0100": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0100.Title", nil, [NSBundle mainBundle], @"Timestamped Logs", @"Tip of the day title, id 0100"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0100.Body", nil, [NSBundle mainBundle], @"Include timestamps in your logs for better tracking and event correlation.", @"Tip of the day body, id 0100") },

            @"0101": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0101.Title", nil, [NSBundle mainBundle], @"LastPass & 1Password", @"Tip of the day title, id 0101"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0101.Body", nil, [NSBundle mainBundle], @"Utilize LastPass or 1Password with the password manager by configuring it in the menu next to the search field.", @"Tip of the day body, id 0101") },

            @"0102": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0102.Title", nil, [NSBundle mainBundle], @"Password Manager Access", @"Tip of the day title, id 0102"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0102.Body", nil, [NSBundle mainBundle], @"Access your password manager without authentication by adjusting the settings via the menu next to its search field.", @"Tip of the day body, id 0102") },

            @"0103": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0103.Title", nil, [NSBundle mainBundle], @"Password Generation", @"Tip of the day title, id 0103"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0103.Body", nil, [NSBundle mainBundle], @"Generate strong, secure passwords using the password manager’s new password generation feature.", @"Tip of the day body, id 0103") },

            @"0104": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0104.Title", nil, [NSBundle mainBundle], @"it2tip Utility", @"Tip of the day title, id 0104"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0104.Body", nil, [NSBundle mainBundle], @"Access tips of the day with the it2tip utility, a command line app. Enable it by installing shell integration and utilities.", @"Tip of the day body, id 0104") },

            @"0105": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0105.Title", nil, [NSBundle mainBundle], @"Auto Shell Integration", @"Tip of the day title, id 0105"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0105.Body", nil, [NSBundle mainBundle], @"Experience automatic shell integration when creating a login shell, removing the need for explicit setup on your Mac.", @"Tip of the day body, id 0105") },

            @"0106": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0106.Title", nil, [NSBundle mainBundle], @"Command Prompt Info", @"Tip of the day title, id 0106"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0106.Body", nil, [NSBundle mainBundle], @"Get detailed information about commands by ⌘-clicking on the command prompt.", @"Tip of the day body, id 0106") },

            @"0107": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0107.Title", nil, [NSBundle mainBundle], @"tmux Integration", @"Tip of the day title, id 0107"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0107.Body", nil, [NSBundle mainBundle], @"Use tmux integration for automatic key bindings that emulate tmux’s shortcuts, configurable via the Leader settings.", @"Tip of the day body, id 0107") },

            @"0108": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0108.Title", nil, [NSBundle mainBundle], @"tmux Clipboard Mirroring", @"Tip of the day title, id 0108"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0108.Body", nil, [NSBundle mainBundle], @"Sync your tmux paste buffer with the local clipboard for seamless integration (requires tmux 3.4).", @"Tip of the day body, id 0108") },

            @"0109": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0109.Title", nil, [NSBundle mainBundle], @"Multi-Cursor in Composer", @"Tip of the day title, id 0109"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0109.Body", nil, [NSBundle mainBundle], @"Enhance your editing in the Composer with multiple cursors, created using ^⇧-up/down or ⌥-drag.", @"Tip of the day body, id 0109") },

            @"0110": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0110.Title", nil, [NSBundle mainBundle], @"Advanced Paste from Composer", @"Tip of the day title, id 0110"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0110.Body", nil, [NSBundle mainBundle], @"Move content from the Composer to the Advanced Paste window with ⌥⌘V for additional editing options.", @"Tip of the day body, id 0110") },

            @"0111": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0111.Title", nil, [NSBundle mainBundle], @"Composer Search", @"Tip of the day title, id 0111"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0111.Body", nil, [NSBundle mainBundle], @"Search within the Composer using ⌘F to quickly find specific text.", @"Tip of the day body, id 0111") },

            @"0112": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0112.Title", nil, [NSBundle mainBundle], @"Resize Composer", @"Tip of the day title, id 0112"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0112.Body", nil, [NSBundle mainBundle], @"Adjust the Composer’s height to suit your needs by dragging its bottom edge.", @"Tip of the day body, id 0112") },

            @"0113": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0113.Title", nil, [NSBundle mainBundle], @"Explain Command", @"Tip of the day title, id 0113"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0113.Body", nil, [NSBundle mainBundle], @"Learn more about your commands by ⌘-clicking in the Composer to open them in explainshell.com.", @"Tip of the day body, id 0113") },

            @"0114": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0114.Title", nil, [NSBundle mainBundle], @"Quick Command Send", @"Tip of the day title, id 0114"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0114.Body", nil, [NSBundle mainBundle], @"Quickly send and remove commands in the Composer using ⌥⇧-enter.", @"Tip of the day body, id 0114") },

            @"0115": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0115.Title", nil, [NSBundle mainBundle], @"Queue Commands", @"Tip of the day title, id 0115"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0115.Body", nil, [NSBundle mainBundle], @"Queue up a command in the Composer to be sent after the current command finishes with ⌥-Enter.", @"Tip of the day body, id 0115") },

            @"0116": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0116.Title", nil, [NSBundle mainBundle], @"Draggable Tip Window", @"Tip of the day title, id 0116"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0116.Body", nil, [NSBundle mainBundle], @"Reposition the Tip of the Day window conveniently on your screen, as it is now draggable.", @"Tip of the day body, id 0116") },

            @"0117": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0117.Title", nil, [NSBundle mainBundle], @"AI Chat", @"Tip of the day title, id 0117"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0117.Body", nil, [NSBundle mainBundle], @"iTerm2 now has an AI Chat feature! Use “Window > AI Chats” or “Edit > Explain Output with AI”. The assistant can interact with your terminal (with your permission) and explain command output, adding annotations right in the terminal.", @"Tip of the day body, id 0117") },

            @"0118": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0118.Title", nil, [NSBundle mainBundle], @"Web Browser Profiles", @"Tip of the day title, id 0118"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0118.Body", nil, [NSBundle mainBundle], @"You can configure a profile to be a web browser! In “Settings > Profiles > General”, set “Profile Type” to “Web Browser”. Key bindings, smart selection, and the password manager all work in browser sessions.", @"Tip of the day body, id 0118"),
                        kTipUrlKey: @"https://iterm2.com/documentation-web.html" },

            @"0119": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0119.Title", nil, [NSBundle mainBundle], @"Adjacent Timestamps", @"Tip of the day title, id 0119"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0119.Body", nil, [NSBundle mainBundle], @"Timestamps can now be shown next to terminal content instead of overlapping. Configure it in “Settings > Profiles > Session > Timestamps”. Right-click on any line and select “Set Baseline for Relative Timestamps” to see time elapsed between lines.", @"Tip of the day body, id 0119") },

            @"0120": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0120.Title", nil, [NSBundle mainBundle], @"Pretty-Print JSON", @"Tip of the day title, id 0120"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0120.Body", nil, [NSBundle mainBundle], @"Select a block of JSON text and choose “Edit > Replace Selection > Replace with Pretty-Printed JSON” to make it readable. Perfect for debugging API responses and log files.", @"Tip of the day body, id 0120") },

            @"0121": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0121.Title", nil, [NSBundle mainBundle], @"Command Palette", @"Tip of the day title, id 0121"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0121.Body", nil, [NSBundle mainBundle], @"Open Quickly (⇧⌘O) is now a command palette! Just type the name of a menu item to activate it.", @"Tip of the day body, id 0121") },

            @"0122": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0122.Title", nil, [NSBundle mainBundle], @"Click Paths in Shell Prompts", @"Tip of the day title, id 0122"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0122.Body", nil, [NSBundle mainBundle], @"Enable “Settings > Profiles > Terminal > Click on a path in a shell prompt to open Navigator” to navigate your filesystem by clicking on paths in your prompt. Requires Shell Integration.", @"Tip of the day body, id 0122") },

            @"0123": @{ kTipTitleKey: NSLocalizedStringWithDefaultValue(@"Tip.0123.Title", nil, [NSBundle mainBundle], @"SSH File Browser", @"Tip of the day title, id 0123"),
                        kTipBodyKey: NSLocalizedStringWithDefaultValue(@"Tip.0123.Body", nil, [NSBundle mainBundle], @"When connected via SSH Integration, use “Shell > ssh > Download Files” to browse and download files from the remote host without opening a new connection. Files on SSH hosts also appear in file open/save dialogs!", @"Tip of the day body, id 0123") },

// IMPORTANT: When updating this, also update it2tip
            };
}

@end
