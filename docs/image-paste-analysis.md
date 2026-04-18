# Image Paste Support — Analysis & Implementation Plan

## Problem

Currently, pasting a screenshot into the iTerm2 terminal requires:
1. Save screenshot to file
2. Drag file to terminal or reference path manually

Users want: **Cmd+V with clipboard image → automatic handling**

## Implementation Approach

### Phase 1: Detect Image in Clipboard

In `PTYTextView.m`, override `paste:`:

```objc
- (IBAction)paste:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    
    // Check for image first
    if ([pb canReadObjectForClasses:@[NSImage.class] options:@{}]) {
        [self handleClipboardImage];
        return;
    }
    
    // Original paste behavior
    [super paste:sender];
}

- (void)handleClipboardImage {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSArray *images = [pb readObjectsForClasses:@[NSImage.class] options:@{}];
    if (images.count == 0) return;
    
    NSImage *image = images.firstObject;
    [self saveAndInjectImage:image];
}
```

### Phase 2: Save to Temp File

```objc
- (void)saveAndInjectImage:(NSImage *)image {
    // Save to ~/Downloads/ or /tmp/
    NSString *filename = [NSString stringWithFormat:@"paste_%@.png",
                          [[NSUUID UUID] UUIDString]];
    NSString *savePath = [NSTemporaryDirectory() 
                          stringByAppendingPathComponent:filename];
    
    NSBitmapImageRep *rep = [NSBitmapImageRep 
                             imageRepWithData:[image TIFFRepresentation]];
    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG 
                                        properties:@{}];
    [pngData writeToFile:savePath atomically:YES];
    
    // Now inject path into terminal
    [self insertText:savePath replacementRange:NSMakeRange(NSNotFound, 0)];
}
```

### Phase 3: Claude Code Integration

If Claude Code is the active process, prepend the image upload command:

```objc
// Detect if claude or codex is active in session
NSString *activeProcess = self.currentSession.foregroundProcessName;
if ([activeProcess isEqualToString:@"claude"]) {
    // Claude Code uses: Type the path, it handles inline images
    [self.currentSession writeTaskWithString:[NSString stringWithFormat:@"%@\n", savePath]];
} else {
    // Generic: just insert the path
    [self insertText:savePath replacementRange:NSMakeRange(NSNotFound, 0)];
}
```

## Files to Modify

- `sources/PTYTextView.m` — override `paste:` action
- `sources/PTYSession.m` — add `foregroundProcessName` helper if not exists

## UX Considerations

- Show a brief notification: "Image saved to /tmp/paste_xxx.png"
- Option to choose save location (Preferences setting)
- Support for multiple images in clipboard

## Status

- [ ] Analysis complete (this document)
- [ ] Implement `paste:` override in PTYTextView
- [ ] Test with Claude Code active session
- [ ] Test with Codex active session
- [ ] Add preference for image save location
