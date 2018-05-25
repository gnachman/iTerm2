
Menu Item Identifiers
---------------------

To refer to a menu item you must use its unique identifier. The kind of identifier you use depends on the version of macOS you have.

For macOS 10.12 and newer, identifiers are stable and do not change over time.

On older versions of macOS, you use `Title Paths`_. A title path is a concatenation of menu item titles. This is because of a limitation imposed by the OS.

----------


^^^^^^^^^^^
Identifiers
^^^^^^^^^^^

Use these identifiers for macOS 10.12 and newer:


======================================================================================= ==============================================================================
Menu Item                                                                               Identifier                                                                    
======================================================================================= ==============================================================================
iTerm2 > About iTerm2                                                                   `About iTerm2`                                                                
iTerm2 > Show Tip of the Day                                                            `Show Tip of the Day`                                                         
iTerm2 > Check for Incompatible Software                                                `Check for Incompatible Software`                                             
iTerm2 > Check For Updates…                                                             `Check For Updates…`                                                          
iTerm2 > Toggle Debug Logging                                                           `Toggle Debug Logging`                                                        
iTerm2 > Copy Performance Stats                                                         `Copy Performance Stats`                                                      
iTerm2 > Capture Metal Frame                                                            `Capture Metal Frame`                                                         
iTerm2 > Preferences...                                                                 `Preferences...`                                                              
iTerm2 > Hide iTerm2                                                                    `Hide iTerm2`                                                                 
iTerm2 > Hide Others                                                                    `Hide Others`                                                                 
iTerm2 > Show All                                                                       `Show All`                                                                    
iTerm2 > Secure Keyboard Entry                                                          `Secure Keyboard Entry`                                                       
iTerm2 > Make iTerm2 Default Term                                                       `Make iTerm2 Default Term`                                                    
iTerm2 > Make Terminal Default Term                                                     `Make Terminal Default Term`                                                  
iTerm2 > Install Shell Integration                                                      `Install Shell Integration`                                                   
iTerm2 > Quit iTerm2                                                                    `Quit iTerm2`                                                                 
Shell > New Window                                                                      `New Window`                                                                  
Shell > New Tab                                                                         `New Tab`                                                                     
Shell > New Tab with Current Profile                                                    `New Tab with Current Profile`                                                
Shell > Duplicate Tab                                                                   `Duplicate Tab`                                                               
Shell > Split Vertically with Current Profile                                           `Split Vertically with Current Profile`                                       
Shell > Split Horizontally with Current Profile                                         `Split Horizontally with Current Profile`                                     
Shell > Split Horizontally…                                                             `Split Horizontally…`                                                         
Shell > Split Vertically…                                                               `Split Vertically…`                                                           
Shell > Save Selected Text…                                                             `Save Selected Text…`                                                         
Shell > Close                                                                           `Close`                                                                       
Shell > Close Terminal Window                                                           `Close Terminal Window`                                                       
Shell > Close All Panes in Tab                                                          `Close All Panes in Tab`                                                      
Shell > Broadcast Input > Send Input to Current Session Only                            `Broadcast Input.Send Input to Current Session Only`                          
Shell > Broadcast Input > Broadcast Input to All Panes in All Tabs                      `Broadcast Input.Broadcast Input to All Panes in All Tabs`                    
Shell > Broadcast Input > Broadcast Input to All Panes in Current Tab                   `Broadcast Input.Broadcast Input to All Panes in Current Tab`                 
Shell > Broadcast Input > Toggle Broadcast Input to Current Session                     `Broadcast Input.Toggle Broadcast Input to Current Session`                   
Shell > Broadcast Input > Show Background Pattern Indicator                             `Broadcast Input.Show Background Pattern Indicator`                           
Shell > tmux > Detach                                                                   `tmux.Detach`                                                                 
Shell > tmux > New Tmux Window                                                          `tmux.New Tmux Window`                                                        
Shell > tmux > New Tmux Tab                                                             `tmux.New Tmux Tab`                                                           
Shell > tmux > Dashboard                                                                `tmux.Dashboard`                                                              
Shell > Page Setup...                                                                   `Page Setup...`                                                               
Shell > Print > Screen                                                                  `Print.Screen`                                                                
Shell > Print > Selection                                                               `Print.Selection`                                                             
Shell > Print > Buffer                                                                  `Print.Buffer`                                                                
Edit > Undo                                                                             `Undo`                                                                        
Edit > Redo                                                                             `Redo`                                                                        
Edit > Cut                                                                              `Cut`                                                                         
Edit > Copy                                                                             `Copy`                                                                        
Edit > Copy with Styles                                                                 `Copy with Styles`                                                            
Edit > Copy Mode                                                                        `Copy Mode`                                                                   
Edit > Paste                                                                            `Paste`                                                                       
Edit > Paste Special > Advanced Paste…                                                  `Paste Special.Advanced Paste…`                                               
Edit > Paste Special > Paste Selection                                                  `Paste Special.Paste Selection`                                               
Edit > Paste Special > Paste File Base64-Encoded                                        `Paste Special.Paste File Base64-Encoded`                                     
Edit > Paste Special > Paste Slowly                                                     `Paste Special.Paste Slowly`                                                  
Edit > Paste Special > Paste Faster                                                     `Paste Special.Paste Faster`                                                  
Edit > Paste Special > Paste Slowly Faster                                              `Paste Special.Paste Slowly Faster`                                           
Edit > Paste Special > Paste Slower                                                     `Paste Special.Paste Slower`                                                  
Edit > Paste Special > Paste Slowly Slower                                              `Paste Special.Paste Slowly Slower`                                           
Edit > Paste Special > Warn Before Multi-Line Paste                                     `Paste Special.Warn Before Multi-Line Paste`                                  
Edit > Paste Special > Limit Multi-Line Paste Warning to Shell Prompt                   `Paste Special.Limit Multi-Line Paste Warning to Shell Prompt`                
Edit > Paste Special > Warn Before Pasting One Line Ending in a Newline at Shell Prompt `Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt`
Edit > Open Selection                                                                   `Open Selection`                                                              
Edit > Select All                                                                       `Select All`                                                                  
Edit > Selection Respects Soft Boundaries                                               `Selection Respects Soft Boundaries`                                          
Edit > Select Output of Last Command                                                    `Select Output of Last Command`                                               
Edit > Select Current Command                                                           `Select Current Command`                                                      
Edit > Find > Find...                                                                   `Find.Find...`                                                                
Edit > Find > Find Next                                                                 `Find.Find Next`                                                              
Edit > Find > Find Previous                                                             `Find.Find Previous`                                                          
Edit > Find > Use Selection for Find                                                    `Find.Use Selection for Find`                                                 
Edit > Find > Jump to Selection                                                         `Find.Jump to Selection`                                                      
Edit > Find > Find URLs                                                                 `Find.Find URLs`                                                              
Edit > Marks and Annotations > Set Mark                                                 `Marks and Annotations.Set Mark`                                              
Edit > Marks and Annotations > Add Annotation at Cursor                                 `Marks and Annotations.Add Annotation at Cursor`                              
Edit > Marks and Annotations > Jump to Mark                                             `Marks and Annotations.Jump to Mark`                                          
Edit > Marks and Annotations > Previous Mark/Annotation                                 `Marks and Annotations.Previous Mark or Annotation`                           
Edit > Marks and Annotations > Next Mark/Annotation                                     `Marks and Annotations.Next Mark or Annotation`                               
Edit > Marks and Annotations > Alerts > Alert on Next Mark                              `Marks and Annotations.Alerts.Alert on Next Mark`                             
Edit > Marks and Annotations > Alerts > Show Modal Alert Box                            `Marks and Annotations.Alerts.Show Modal Alert Box`                           
Edit > Marks and Annotations > Alerts > Post Notification                               `Marks and Annotations.Alerts.Post Notification`                              
Edit > Clear Buffer                                                                     `Clear Buffer`                                                                
Edit > Clear Scrollback Buffer                                                          `Clear Scrollback Buffer`                                                     
View > Show Tabs in Fullscreen                                                          `Show Tabs in Fullscreen`                                                     
View > Toggle Full Screen                                                               `Toggle Full Screen`                                                          
View > Use Transparency                                                                 `Use Transparency`                                                            
View > Zoom In on Selection                                                             `Zoom In on Selection`                                                        
View > Zoom Out                                                                         `Zoom Out`                                                                    
View > Find Cursor                                                                      `Find Cursor`                                                                 
View > Show Cursor Guide                                                                `Show Cursor Guide`                                                           
View > Show Timestamps                                                                  `Show Timestamps`                                                             
View > Show Annotations                                                                 `Show Annotations`                                                            
View > Auto Command Completion                                                          `Auto Command Completion`                                                     
View > Open Quickly                                                                     `Open Quickly`                                                                
View > Maximize Active Pane                                                             `Maximize Active Pane`                                                        
View > Make Text Bigger                                                                 `Make Text Bigger`                                                            
View > Make Text Normal Size                                                            `Make Text Normal Size`                                                       
View > Restore Text and Session Size                                                    `Restore Text and Session Size`                                               
View > Make Text Smaller                                                                `Make Text Smaller`                                                           
View > Start Instant Replay                                                             `Start Instant Replay`                                                        
Session > Edit Session…                                                                 `Edit Session…`                                                               
Session > Run Coprocess…                                                                `Run Coprocess…`                                                              
Session > Stop Coprocess                                                                `Stop Coprocess`                                                              
Session > Restart Session                                                               `Restart Session`                                                             
Session > Open Autocomplete…                                                            `Open Autocomplete…`                                                          
Session > Open Command History…                                                         `Open Command History…`                                                       
Session > Open Recent Directories…                                                      `Open Recent Directories…`                                                    
Session > Open Paste History…                                                           `Open Paste History…`                                                         
Session > Reset                                                                         `Reset`                                                                       
Session > Reset Character Set                                                           `Reset Character Set`                                                         
Session > Log > Start                                                                   `Log.Start`                                                                   
Session > Log > Stop                                                                    `Log.Stop`                                                                    
Session > Bury Session                                                                  `Bury Session`                                                                
Scripts > Install Python Runtime                                                        `Install Python Runtime`                                                      
Scripts > New Python Script                                                             `New Python Script`                                                           
Scripts > Reveal Scripts in Finder                                                      `Reveal in Finder`                                                            
Scripts > Open Python REPL                                                              `Open Interactive Window`                                                     
Scripts > Script Console                                                                `Script Console`                                                              
Profiles > Open Profiles…                                                               `Open Profiles…`                                                              
Profiles > Press Option for New Window                                                  `Press Option for New Window`                                                 
Profiles > Open In New Window                                                           `Open In New Window`                                                          
Toolbelt > Show Toolbelt                                                                `Show Toolbelt`                                                               
Toolbelt > Set Default Width                                                            `Set Default Width`                                                           
Window > Minimize                                                                       `Minimize`                                                                    
Window > Zoom                                                                           `Zoom`                                                                        
Window > Arrange Windows Horizontally                                                   `Arrange Windows Horizontally`                                                
Window > Exposé all Tabs                                                                `Exposé all Tabs`                                                             
Window > Save Window Arrangement                                                        `Save Window Arrangement`                                                     
Window > Save Current Window as Arrangement                                             `Save Current Window as Arrangement`                                          
Window > Select Split Pane > Select Pane Above                                          `Select Split Pane.Select Pane Above`                                         
Window > Select Split Pane > Select Pane Below                                          `Select Split Pane.Select Pane Below`                                         
Window > Select Split Pane > Select Pane Left                                           `Select Split Pane.Select Pane Left`                                          
Window > Select Split Pane > Select Pane Right                                          `Select Split Pane.Select Pane Right`                                         
Window > Select Split Pane > Next Pane                                                  `Select Split Pane.Next Pane`                                                 
Window > Select Split Pane > Previous Pane                                              `Select Split Pane.Previous Pane`                                             
Window > Resize Split Pane > Move Divider Up                                            `Resize Split Pane.Move Divider Up`                                           
Window > Resize Split Pane > Move Divider Down                                          `Resize Split Pane.Move Divider Down`                                         
Window > Resize Split Pane > Move Divider Left                                          `Resize Split Pane.Move Divider Left`                                         
Window > Resize Split Pane > Move Divider Right                                         `Resize Split Pane.Move Divider Right`                                        
Window > Resize Window > Decrease Height                                                `Resize Window.Decrease Height`                                               
Window > Resize Window > Increase Height                                                `Resize Window.Increase Height`                                               
Window > Resize Window > Decrease Width                                                 `Resize Window.Decrease Width`                                                
Window > Resize Window > Increase Width                                                 `Resize Window.Increase Width`                                                
Window > Select Next Tab                                                                `Select Next Tab`                                                             
Window > Select Previous Tab                                                            `Select Previous Tab`                                                         
Window > Move Tab Left                                                                  `Move Tab Left`                                                               
Window > Move Tab Right                                                                 `Move Tab Right`                                                              
Window > Password Manager                                                               `Password Manager`                                                            
Window > Pin Hotkey Window                                                              `Pin Hotkey Window`                                                           
Window > Bring All To Front                                                             `Bring All To Front`                                                          
Help > iTerm2 Help                                                                      `iTerm2 Help`                                                                 
Help > Copy Mode Shortcuts                                                              `Copy Mode Shortcuts`                                                         
Help > Open Source Licenses                                                             `Open Source Licenses`                                                        
======================================================================================= ==============================================================================


----------

^^^^^^^^^^^
Title Paths
^^^^^^^^^^^

Use these title paths for macOS 10.11 and earlier:


======================================================================================= ===================================================================================
Menu Item                                                                               Title Path                                                                         
======================================================================================= ===================================================================================
iTerm2 > About iTerm2                                                                   `iTerm2.About iTerm2`                                                              
iTerm2 > Show Tip of the Day                                                            `iTerm2.Show Tip of the Day`                                                       
iTerm2 > Check for Incompatible Software                                                `iTerm2.Check for Incompatible Software`                                           
iTerm2 > Check For Updates…                                                             `iTerm2.Check For Updates…`                                                        
iTerm2 > Toggle Debug Logging                                                           `iTerm2.Toggle Debug Logging`                                                      
iTerm2 > Copy Performance Stats                                                         `iTerm2.Copy Performance Stats`                                                    
iTerm2 > Capture Metal Frame                                                            `iTerm2.Capture Metal Frame`                                                       
iTerm2 > Preferences...                                                                 `iTerm2.Preferences...`                                                            
iTerm2 > Hide iTerm2                                                                    `iTerm2.Hide iTerm2`                                                               
iTerm2 > Hide Others                                                                    `iTerm2.Hide Others`                                                               
iTerm2 > Show All                                                                       `iTerm2.Show All`                                                                  
iTerm2 > Secure Keyboard Entry                                                          `iTerm2.Secure Keyboard Entry`                                                     
iTerm2 > Make iTerm2 Default Term                                                       `iTerm2.Make iTerm2 Default Term`                                                  
iTerm2 > Make Terminal Default Term                                                     `iTerm2.Make Terminal Default Term`                                                
iTerm2 > Install Shell Integration                                                      `iTerm2.Install Shell Integration`                                                 
iTerm2 > Quit iTerm2                                                                    `iTerm2.Quit iTerm2`                                                               
Shell > New Window                                                                      `Shell.New Window`                                                                 
Shell > New Tab                                                                         `Shell.New Tab`                                                                    
Shell > New Tab with Current Profile                                                    `Shell.New Tab with Current Profile`                                               
Shell > Duplicate Tab                                                                   `Shell.Duplicate Tab`                                                              
Shell > Split Vertically with Current Profile                                           `Shell.Split Vertically with Current Profile`                                      
Shell > Split Horizontally with Current Profile                                         `Shell.Split Horizontally with Current Profile`                                    
Shell > Split Horizontally…                                                             `Shell.Split Horizontally…`                                                        
Shell > Split Vertically…                                                               `Shell.Split Vertically…`                                                          
Shell > Save Selected Text…                                                             `Shell.Save Selected Text…`                                                        
Shell > Close                                                                           `Shell.Close`                                                                      
Shell > Close Terminal Window                                                           `Shell.Close Terminal Window`                                                      
Shell > Close All Panes in Tab                                                          `Shell.Close All Panes in Tab`                                                     
Shell > Broadcast Input > Send Input to Current Session Only                            `Shell.Broadcast Input.Send Input to Current Session Only`                         
Shell > Broadcast Input > Broadcast Input to All Panes in All Tabs                      `Shell.Broadcast Input.Broadcast Input to All Panes in All Tabs`                   
Shell > Broadcast Input > Broadcast Input to All Panes in Current Tab                   `Shell.Broadcast Input.Broadcast Input to All Panes in Current Tab`                
Shell > Broadcast Input > Toggle Broadcast Input to Current Session                     `Shell.Broadcast Input.Toggle Broadcast Input to Current Session`                  
Shell > Broadcast Input > Show Background Pattern Indicator                             `Shell.Broadcast Input.Show Background Pattern Indicator`                          
Shell > tmux > Detach                                                                   `Shell.tmux.Detach`                                                                
Shell > tmux > New Tmux Window                                                          `Shell.tmux.New Tmux Window`                                                       
Shell > tmux > New Tmux Tab                                                             `Shell.tmux.New Tmux Tab`                                                          
Shell > tmux > Dashboard                                                                `Shell.tmux.Dashboard`                                                             
Shell > Page Setup...                                                                   `Shell.Page Setup...`                                                              
Shell > Print > Screen                                                                  `Shell.Print.Screen`                                                               
Shell > Print > Selection                                                               `Shell.Print.Selection`                                                            
Shell > Print > Buffer                                                                  `Shell.Print.Buffer`                                                               
Edit > Undo                                                                             `Edit.Undo`                                                                        
Edit > Redo                                                                             `Edit.Redo`                                                                        
Edit > Cut                                                                              `Edit.Cut`                                                                         
Edit > Copy                                                                             `Edit.Copy`                                                                        
Edit > Copy with Styles                                                                 `Edit.Copy with Styles`                                                            
Edit > Copy Mode                                                                        `Edit.Copy Mode`                                                                   
Edit > Paste                                                                            `Edit.Paste`                                                                       
Edit > Paste Special > Advanced Paste…                                                  `Edit.Paste Special.Advanced Paste…`                                               
Edit > Paste Special > Paste Selection                                                  `Edit.Paste Special.Paste Selection`                                               
Edit > Paste Special > Paste File Base64-Encoded                                        `Edit.Paste Special.Paste File Base64-Encoded`                                     
Edit > Paste Special > Paste Slowly                                                     `Edit.Paste Special.Paste Slowly`                                                  
Edit > Paste Special > Paste Faster                                                     `Edit.Paste Special.Paste Faster`                                                  
Edit > Paste Special > Paste Slowly Faster                                              `Edit.Paste Special.Paste Slowly Faster`                                           
Edit > Paste Special > Paste Slower                                                     `Edit.Paste Special.Paste Slower`                                                  
Edit > Paste Special > Paste Slowly Slower                                              `Edit.Paste Special.Paste Slowly Slower`                                           
Edit > Paste Special > Warn Before Multi-Line Paste                                     `Edit.Paste Special.Warn Before Multi-Line Paste`                                  
Edit > Paste Special > Limit Multi-Line Paste Warning to Shell Prompt                   `Edit.Paste Special.Limit Multi-Line Paste Warning to Shell Prompt`                
Edit > Paste Special > Warn Before Pasting One Line Ending in a Newline at Shell Prompt `Edit.Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt`
Edit > Open Selection                                                                   `Edit.Open Selection`                                                              
Edit > Select All                                                                       `Edit.Select All`                                                                  
Edit > Selection Respects Soft Boundaries                                               `Edit.Selection Respects Soft Boundaries`                                          
Edit > Select Output of Last Command                                                    `Edit.Select Output of Last Command`                                               
Edit > Select Current Command                                                           `Edit.Select Current Command`                                                      
Edit > Find > Find...                                                                   `Edit.Find.Find...`                                                                
Edit > Find > Find Next                                                                 `Edit.Find.Find Next`                                                              
Edit > Find > Find Previous                                                             `Edit.Find.Find Previous`                                                          
Edit > Find > Use Selection for Find                                                    `Edit.Find.Use Selection for Find`                                                 
Edit > Find > Jump to Selection                                                         `Edit.Find.Jump to Selection`                                                      
Edit > Find > Find URLs                                                                 `Edit.Find.Find URLs`                                                              
Edit > Marks and Annotations > Set Mark                                                 `Edit.Marks and Annotations.Set Mark`                                              
Edit > Marks and Annotations > Add Annotation at Cursor                                 `Edit.Marks and Annotations.Add Annotation at Cursor`                              
Edit > Marks and Annotations > Jump to Mark                                             `Edit.Marks and Annotations.Jump to Mark`                                          
Edit > Marks and Annotations > Previous Mark/Annotation                                 `Edit.Marks and Annotations.Previous Mark/Annotation`                              
Edit > Marks and Annotations > Next Mark/Annotation                                     `Edit.Marks and Annotations.Next Mark/Annotation`                                  
Edit > Marks and Annotations > Alerts > Alert on Next Mark                              `Edit.Marks and Annotations.Alerts.Alert on Next Mark`                             
Edit > Marks and Annotations > Alerts > Show Modal Alert Box                            `Edit.Marks and Annotations.Alerts.Show Modal Alert Box`                           
Edit > Marks and Annotations > Alerts > Post Notification                               `Edit.Marks and Annotations.Alerts.Post Notification`                              
Edit > Clear Buffer                                                                     `Edit.Clear Buffer`                                                                
Edit > Clear Scrollback Buffer                                                          `Edit.Clear Scrollback Buffer`                                                     
View > Show Tabs in Fullscreen                                                          `View.Show Tabs in Fullscreen`                                                     
View > Toggle Full Screen                                                               `View.Toggle Full Screen`                                                          
View > Use Transparency                                                                 `View.Use Transparency`                                                            
View > Zoom In on Selection                                                             `View.Zoom In on Selection`                                                        
View > Zoom Out                                                                         `View.Zoom Out`                                                                    
View > Find Cursor                                                                      `View.Find Cursor`                                                                 
View > Show Cursor Guide                                                                `View.Show Cursor Guide`                                                           
View > Show Timestamps                                                                  `View.Show Timestamps`                                                             
View > Show Annotations                                                                 `View.Show Annotations`                                                            
View > Auto Command Completion                                                          `View.Auto Command Completion`                                                     
View > Open Quickly                                                                     `View.Open Quickly`                                                                
View > Maximize Active Pane                                                             `View.Maximize Active Pane`                                                        
View > Make Text Bigger                                                                 `View.Make Text Bigger`                                                            
View > Make Text Normal Size                                                            `View.Make Text Normal Size`                                                       
View > Restore Text and Session Size                                                    `View.Restore Text and Session Size`                                               
View > Make Text Smaller                                                                `View.Make Text Smaller`                                                           
View > Start Instant Replay                                                             `View.Start Instant Replay`                                                        
Session > Edit Session…                                                                 `Session.Edit Session…`                                                            
Session > Run Coprocess…                                                                `Session.Run Coprocess…`                                                           
Session > Stop Coprocess                                                                `Session.Stop Coprocess`                                                           
Session > Restart Session                                                               `Session.Restart Session`                                                          
Session > Open Autocomplete…                                                            `Session.Open Autocomplete…`                                                       
Session > Open Command History…                                                         `Session.Open Command History…`                                                    
Session > Open Recent Directories…                                                      `Session.Open Recent Directories…`                                                 
Session > Open Paste History…                                                           `Session.Open Paste History…`                                                      
Session > Reset                                                                         `Session.Reset`                                                                    
Session > Reset Character Set                                                           `Session.Reset Character Set`                                                      
Session > Log > Start                                                                   `Session.Log.Start`                                                                
Session > Log > Stop                                                                    `Session.Log.Stop`                                                                 
Session > Bury Session                                                                  `Session.Bury Session`                                                             
Scripts > Install Python Runtime                                                        `Scripts.Install Python Runtime`                                                   
Scripts > New Python Script                                                             `Scripts.New Python Script`                                                        
Scripts > Reveal Scripts in Finder                                                      `Scripts.Reveal Scripts in Finder`                                                 
Scripts > Open Python REPL                                                              `Scripts.Open Python REPL`                                                         
Scripts > Script Console                                                                `Scripts.Script Console`                                                           
Profiles > Open Profiles…                                                               `Profiles.Open Profiles…`                                                          
Profiles > Press Option for New Window                                                  `Profiles.Press Option for New Window`                                             
Profiles > Open In New Window                                                           `Profiles.Open In New Window`                                                      
Toolbelt > Show Toolbelt                                                                `Toolbelt.Show Toolbelt`                                                           
Toolbelt > Set Default Width                                                            `Toolbelt.Set Default Width`                                                       
Window > Minimize                                                                       `Window.Minimize`                                                                  
Window > Zoom                                                                           `Window.Zoom`                                                                      
Window > Arrange Windows Horizontally                                                   `Window.Arrange Windows Horizontally`                                              
Window > Exposé all Tabs                                                                `Window.Exposé all Tabs`                                                           
Window > Save Window Arrangement                                                        `Window.Save Window Arrangement`                                                   
Window > Save Current Window as Arrangement                                             `Window.Save Current Window as Arrangement`                                        
Window > Select Split Pane > Select Pane Above                                          `Window.Select Split Pane.Select Pane Above`                                       
Window > Select Split Pane > Select Pane Below                                          `Window.Select Split Pane.Select Pane Below`                                       
Window > Select Split Pane > Select Pane Left                                           `Window.Select Split Pane.Select Pane Left`                                        
Window > Select Split Pane > Select Pane Right                                          `Window.Select Split Pane.Select Pane Right`                                       
Window > Select Split Pane > Next Pane                                                  `Window.Select Split Pane.Next Pane`                                               
Window > Select Split Pane > Previous Pane                                              `Window.Select Split Pane.Previous Pane`                                           
Window > Resize Split Pane > Move Divider Up                                            `Window.Resize Split Pane.Move Divider Up`                                         
Window > Resize Split Pane > Move Divider Down                                          `Window.Resize Split Pane.Move Divider Down`                                       
Window > Resize Split Pane > Move Divider Left                                          `Window.Resize Split Pane.Move Divider Left`                                       
Window > Resize Split Pane > Move Divider Right                                         `Window.Resize Split Pane.Move Divider Right`                                      
Window > Resize Window > Decrease Height                                                `Window.Resize Window.Decrease Height`                                             
Window > Resize Window > Increase Height                                                `Window.Resize Window.Increase Height`                                             
Window > Resize Window > Decrease Width                                                 `Window.Resize Window.Decrease Width`                                              
Window > Resize Window > Increase Width                                                 `Window.Resize Window.Increase Width`                                              
Window > Select Next Tab                                                                `Window.Select Next Tab`                                                           
Window > Select Previous Tab                                                            `Window.Select Previous Tab`                                                       
Window > Move Tab Left                                                                  `Window.Move Tab Left`                                                             
Window > Move Tab Right                                                                 `Window.Move Tab Right`                                                            
Window > Password Manager                                                               `Window.Password Manager`                                                          
Window > Pin Hotkey Window                                                              `Window.Pin Hotkey Window`                                                         
Window > Bring All To Front                                                             `Window.Bring All To Front`                                                        
Help > iTerm2 Help                                                                      `Help.iTerm2 Help`                                                                 
Help > Copy Mode Shortcuts                                                              `Help.Copy Mode Shortcuts`                                                         
Help > Open Source Licenses                                                             `Help.Open Source Licenses`                                                        
======================================================================================= ===================================================================================

----

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`

