//  PathIcon.m
//  An NXIcon subclass that implements file operations.
//
//  PathIcon holds information about object(file, dir) path. Set with setPath:
//  method. Any other metainformation (e.g. device for mount point) set with
//  setInfo: method.


#import <AppKit/AppKit.h>
#import <NXSystem/NXSystemInfo.h>
#import <NXSystem/NXMouse.h>

#import "Controller+NSWorkspace.h"
#import "FileViewer.h"
#import <Operations/ProcessManager.h>
#import "PathIcon.h"

@implementation PathIcon (Private)

- (NSEvent *)_waitForSecondMouseClick
{
  unsigned  eventMask = (NSLeftMouseDownMask | NSLeftMouseUpMask
			 | NSPeriodicMask | NSOtherMouseUpMask 
			 | NSRightMouseUpMask);
  NSEvent   *event = nil;

  event = [[self window]
    nextEventMatchingMask:eventMask
		untilDate:[NSDate dateWithTimeIntervalSinceNow:0.30]
		   inMode:NSEventTrackingRunLoopMode
		  dequeue:NO];
  return event;
}

@end

@implementation PathIcon

//============================================================================
// Init and destroy
//============================================================================

- init
{
  [super init];

  // registerForDraggedTypes: must call view that holds icon (Shelf, Path).
  // Calling it here make shelf icons continuosly added and removed
  // while dragged.
//  [self registerForDraggedTypes:
//       [NSArray arrayWithObject:NSFilenamesPboardType]];

  doubleClickPassesClick = YES;
  return self;
}

- (void)dealloc
{
  TEST_RELEASE(paths);
  TEST_RELEASE(info);

  [super dealloc];
}

// Overriding
- (void)mouseDown:(NSEvent *)ev
{
  NSInteger clickCount;
  
  if (target == nil || isSelectable == NO || [ev type] != NSLeftMouseDown) {
    return;
  }
  // NSLog(@"PathIcon: mouseDown: %@", paths);
  
  clickCount = [ev clickCount];
  modifierFlags = [ev modifierFlags];
  
  [(NXIconView *)[self superview] selectIcons:[NSSet setWithObject:self]
                                withModifiers:modifierFlags];
  
  // Dragging
  if ([target respondsToSelector:dragAction]) {
    // NSLog(@"[PathIcon-mouseDown]: DRAGGING");
    NSPoint   startPoint = [ev locationInWindow];
    NSInteger eventMask = NSLeftMouseDraggedMask | NSLeftMouseUpMask;
    NSInteger moveThreshold = [[[NXMouse new] autorelease] accelerationThreshold];
    
    while ([(ev = [_window nextEventMatchingMask:eventMask])
             type] != NSLeftMouseUp) {
      NSPoint endPoint = [ev locationInWindow];
      if (absolute_value(startPoint.x - endPoint.x) > moveThreshold ||
          absolute_value(startPoint.y - endPoint.y) > moveThreshold) {
        [target performSelector:dragAction withObject:self withObject:ev];
        return;
      }
    }
  }
  [_window makeFirstResponder:[longLabel nextKeyView]];
  // Clicking
  if (clickCount == 2) {
    // NSLog(@"PathIcon: 2 mouseDown: %@", paths);
    if ([target respondsToSelector:doubleAction]) {
      [target performSelector:doubleAction withObject:self];
    }
  }
  else if (clickCount == 1 || clickCount > 2) {
    // NSLog(@"PathIcon: 1 || >2 mouseDown: %@", paths);
    if (!doubleClickPassesClick && [self _waitForSecondMouseClick] != nil) {
      return;
    }
    if ([target respondsToSelector:action]) {
      [target performSelector:action withObject:self];
    }
  }  
}

// Addons
- (void)setPaths:(NSArray *)newPaths
{
  ASSIGN(paths, newPaths);
  
  if ([paths count] > 1)
    {
      [self setLabelString:
              [NSString stringWithFormat:_(@"%d items"),[paths count]]];
    }
  else
    {
      NSString *path = [paths objectAtIndex:0];
      
      if ([[path pathComponents] count] == 1)
        {
          [self setLabelString:[NXSystemInfo hostName]];
        }
      else
        {
          [self setLabelString:[path lastPathComponent]];
        }
    }
}

- (NSArray *)paths
{
  return paths;
}

- (void)setInfo:(NSDictionary *)anInfo
{
  ASSIGN(info, [anInfo copy]);
}

- (NSDictionary *)info
{
  return info;
}

- (void)setDoubleClickPassesClick:(BOOL)isPass
{
  doubleClickPassesClick = isPass;
}

- (BOOL)isDoubleClickPassesClick
{
  return doubleClickPassesClick;
}

- (BOOL)becomeFirstResponder
{
  return NO;
}

//============================================================================
// Drag and drop
//============================================================================

// --- NSDraggingSource must have 'draggingSourceOperationMaskForLocal:'
// catched by enclosing view (PathView, ShelfView) and dispathed to
// 'delegate' - FileViewer 'draggingSourceOperationMaskForLocal:iconView:'
// method.

// --- NSDraggingDestination

#define PASTEBOARD [sender draggingPasteboard]

- (NSDragOperation)_draggingDestinationMaskForPaths:(NSArray *)sourcePaths
                                           intoPath:(NSString *)destPath
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString      *realPath;
  unsigned int  mask = (NSDragOperationCopy | NSDragOperationMove | 
                        NSDragOperationLink | NSDragOperationDelete);

  if ([fileManager isWritableFileAtPath:destPath] == NO) {
    NSLog(@"[FileViewer] %@ is not writable!", destPath);
    return NSDragOperationNone;
  }

  if ([[[fileManager fileAttributesAtPath:destPath traverseLink:YES]
         fileType] isEqualToString:NSFileTypeDirectory] == NO) {
    NSLog(@"[FileViewer] destination path `%@` is not a directory!", destPath);
    return NSDragOperationNone;
  }

  for (NSString *path in sourcePaths) {
    NSRange r;

    if ([fileManager isDeletableFileAtPath:path] == NO) {
      NSLog(@"[FileViewer] path %@ can not be deleted."
            @"Disabling Move and Delete operation.", path);
      mask ^= (NSDragOperationMove | NSDragOperationDelete);
    }

    if ([path isEqualToString:destPath]) {
      NSLog(@"[FileViewer] source and destination paths are equal "
            @"(%@ == %@)", path, destPath);
      return NSDragOperationNone;
    }

    if ([[path stringByDeletingLastPathComponent] isEqualToString:destPath]) {
      NSLog(@"[FileViewer] `%@` already exists in `%@`", path, destPath);
      return NSDragOperationNone;
    }
  }

  return mask;
}

// - Before the Image is Released
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSString *destPath;
  NSArray  *sourcePaths;

  sourcePaths = [PASTEBOARD propertyListForType:NSFilenamesPboardType];
  destPath = [paths objectAtIndex:0];
  
  NSLog(@"[PathIcon] draggingEntered: %@(%@) -> %@",
        [[sender draggingSource] className], [delegate className], destPath);

  if ([sender draggingSource] == self) {
    draggingMask = NSDragOperationNone;
  }
  else if (![sourcePaths isKindOfClass:[NSArray class]] 
	   || [sourcePaths count] == 0) {
    NSLog(@"[PathIcon] source path list is not NSArray or NSArray is empty!");
    draggingMask = NSDragOperationNone;
  }
  else {
    draggingMask = [self _draggingDestinationMaskForPaths:sourcePaths
                                                 intoPath:destPath];
  }
  
  if (draggingMask != NSDragOperationNone) {
    [self setIconImage:[[NSApp delegate] openIconForDirectory:destPath]];
  }

  return draggingMask;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  // NSLog(@"[PathIcon] draggingUpdated: mask - %i", draggingMask);
  return draggingMask;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  Controller *wsDelegate = [NSApp delegate];
  
  NSLog(@"[PathIcon] draggingExited");
  if (draggingMask != NSDragOperationNone)
    {
      [self setIconImage:[wsDelegate iconForFile:[paths objectAtIndex:0]]];
    }
}

// - After the Image is Released
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSMutableArray *filenames = [NSMutableArray array];
  NSArray        *sourcePaths;
  NSString       *sourceDir;
  unsigned int   mask;
  unsigned int   opType = NSDragOperationNone;

  sourcePaths = [PASTEBOARD propertyListForType:NSFilenamesPboardType];
  // construct an array holding only the trailing filenames
  for (NSString *path in sourcePaths) {
    [filenames addObject:[path lastPathComponent]];
  }

  mask = [sender draggingSourceOperationMask];
  
  if (mask & NSDragOperationMove) {
    opType = MoveOperation;
  }
  else if (mask & NSDragOperationCopy) {
    opType = CopyOperation;
  }
  else if (mask & NSDragOperationLink) {
    opType = LinkOperation;
  }
  else {
    return NO;
  }

  sourceDir = [[sourcePaths objectAtIndex:0] stringByDeletingLastPathComponent];
  [[ProcessManager shared] startOperationWithType:opType
                                           source:sourceDir
                                           target:[paths objectAtIndex:0]
                                            files:filenames];

  return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  [self draggingExited:sender];
}

@end
