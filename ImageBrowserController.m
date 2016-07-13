/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
  See LICENSE.txt for this sample’s licensing information
  
  Abstract:
  IKImageBrowserView is a view that can display and browse images and movies.
   This sample code demonstrate how to use it in a Cocoa Application. 
 */

@import Quartz;   // for IKImageBrowserView

#import "ImageBrowserController.h"

// our data source object for the image browser
@interface myImageObject : NSObject

@property (strong) NSURL *url;

@end


#pragma mark -

@implementation myImageObject

#pragma mark - Item data source protocol

// required methods of the IKImageBrowserItem protocol

// let the image browser knows we use a URL representation
- (NSString *)imageRepresentationType
{
    return IKImageBrowserNSURLRepresentationType;
}

// give our representation to the image browser
- (id)imageRepresentation
{
    return self.url;
}

// use the absolute filepath of our URL as identifier
- (NSString *)imageUID
{
    return self.url.path;
}

@end


#pragma mark -

@interface ImageBrowserController ()

@property (weak) IBOutlet IKImageBrowserView *imageBrowser;

@property (strong) NSMutableArray *images;
@property (strong) NSMutableArray *importedImages;

- (IBAction)addImageButtonClicked:(id)sender;
- (IBAction)zoomSliderDidChange:(id)sender;

@end


#pragma mark -

@implementation ImageBrowserController

// -------------------------------------------------------------------------
//  viewDidLoad
// -------------------------------------------------------------------------
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // create two arrays : the first one is our datasource representation,
    // the second one are temporary imported images (for thread safeness) 
    //
    _images = [[NSMutableArray alloc] init];
    _importedImages = [[NSMutableArray alloc] init];
    
    // allow reordering, animations et set draggind destination delegate
    [self.imageBrowser setAllowsReordering:YES];
    [self.imageBrowser setAnimates:YES];
    [self.imageBrowser setDraggingDestinationDelegate:self];
}

// -------------------------------------------------------------------------
//  updateDatasource
//
//  Entry point for reloading image-browser's data and setNeedsDisplay.
// -------------------------------------------------------------------------
- (void)updateDatasource
{
    // update our datasource, add recently imported items
    [self.images addObjectsFromArray:self.importedImages];
	
	// empty our temporary array
    [self.importedImages removeAllObjects];
    
    // reload the image browser and set needs display
    [self.imageBrowser reloadData];
}


#pragma mark - Import images from file system

// -------------------------------------------------------------------------
//	isImageFile:filePath
//
//	This utility method indicates if the file located at 'filePath' is
//	an image file based on the UTI. It relies on the ImageIO framework for the
//	supported type identifiers.
//
// -------------------------------------------------------------------------
- (BOOL)isImageFile:(NSString *)filePath
{
    BOOL isImageFile = NO;
    
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)filePath, kCFURLPOSIXPathStyle, FALSE);
    
    LSItemInfoRecord info;
    if (LSCopyItemInfoForURL(url, kLSRequestExtension | kLSRequestTypeCreator, &info) == noErr)
    {
        // obtain the UTI using the file information
        CFStringRef	uti = NULL;
        
        // if there is a file extension, get the UTI
        if (info.extension != NULL)
        {
            uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, info.extension, kUTTypeData);
            CFRelease(info.extension);
        }
        
        // no UTI yet
        if (uti == NULL)
        {
            // if there is an OSType, get the UTI
            CFStringRef typeString = UTCreateStringForOSType(info.filetype);
            if ( typeString != NULL)
            {
                uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, typeString, kUTTypeData);
                CFRelease(typeString);
            }
        }
        
        // verify that this is a file that the ImageIO framework supports
        if (uti != NULL)
        {
            CFArrayRef  supportedTypes = CGImageSourceCopyTypeIdentifiers();
            CFIndex	i, typeCount = CFArrayGetCount(supportedTypes);
            
            for (i = 0; i < typeCount; i++)
            {
                if (UTTypeConformsTo(uti, (CFStringRef)CFArrayGetValueAtIndex(supportedTypes, i)))
                {
                    isImageFile = YES;
                    break;
                }
            }
            
            CFRelease(supportedTypes);
            CFRelease(uti);
        }
    }
    
    CFRelease(url);
    
    return isImageFile;
}

// -------------------------------------------------------------------------
//	addImagesWithPath:url
// -------------------------------------------------------------------------
- (void)addImagesWithPath:(NSURL *)url
{
    BOOL dir;
    [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&dir];
    if (dir)
    {
        // load all the images in this directory
        NSArray *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:url.path error:nil];
        
        // parse the directory content
        for (NSUInteger i = 0; i < content.count; i++)
        {
            NSURL *imageURL = [NSURL fileURLWithPath:[url.path stringByAppendingPathComponent:content[i]]];
            [self addAnImageWithPath:imageURL];
        }
    }
    else
    {
        // single image, just load the one
        [self addAnImageWithPath:url];
    }
}

// -------------------------------------------------------------------------
//	addAnImageWithPath:url
// -------------------------------------------------------------------------
- (void)addAnImageWithPath:(NSURL *)url
{
    BOOL addObject = NO;
    
    NSDictionary *fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if (fileAttribs != nil)
    {
        // check for packages
        if ([NSFileTypeDirectory isEqualTo:fileAttribs[NSFileType]])
        {
            if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath:url.path] == NO)
            {
                addObject = YES;	// if it is a file, it's OK to add
            }
        }
        else
        {
            addObject = YES;	// it is a file, so it's OK to add
        }
    }
    
    if (addObject && [self isImageFile:url.path])
    {
        // add a path to the temporary images array
        myImageObject *p = [[myImageObject alloc] init];
        p.url = url;
        [self.importedImages addObject:p];
    }
}


#pragma mark - Actions

// -------------------------------------------------------------------------
//	addImageButtonClicked:sender
//
//	The user clicked the Add Photos button.
// -------------------------------------------------------------------------
- (IBAction)addImageButtonClicked:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseDirectories = YES;
    openPanel.allowsMultipleSelection = YES;
    
    void (^openPanelHandler)(NSInteger) = ^(NSInteger returnCode) {
        if (returnCode == NSFileHandlingPanelOKButton)
        {
            // asynchronously process all URLs from our open panel
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                for (NSURL *url in openPanel.URLs)
                {
                    [self addImagesWithPath:url];
                }
                
                // back on the main queue update the data source in the main thread
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self updateDatasource];
                });
            });
        }
    };
    
    [openPanel beginSheetModalForWindow:self.view.window completionHandler:openPanelHandler];
}

// -------------------------------------------------------------------------
//  zoomSliderDidChange:sender:
//
//  Action called when the zoom slider did change.
// -------------------------------------------------------------------------
- (IBAction)zoomSliderDidChange:(id)sender
{
	// update the zoom value to scale images
    [self.imageBrowser setZoomValue:[sender floatValue]];
	
	// redisplay
    [self.imageBrowser setNeedsDisplay:YES];
}


#pragma mark - IKImageBrowserDataSource

// -------------------------------------------------------------------------
//  numberOfItemsInImageBrowser:view:
//
//  Our datasource representation is a simple mutable array.
// -------------------------------------------------------------------------
- (NSUInteger)numberOfItemsInImageBrowser:(IKImageBrowserView *)view
{
	// item count to display is our datasource item count
    return self.images.count;
}

// -------------------------------------------------------------------------
//	imageBrowser:view:index:
// -------------------------------------------------------------------------
- (id)imageBrowser:(IKImageBrowserView *)view itemAtIndex:(NSUInteger)index
{
    return self.images[index];
}


// implement some optional methods of the image-browser's datasource protocol to be able to remove and reoder items

// -------------------------------------------------------------------------
//  removeItemsAtIndexes:indexes:
//
//  The user wants to delete images, so remove these entries from our datasource.
// -------------------------------------------------------------------------
- (void)imageBrowser:(IKImageBrowserView *)view removeItemsAtIndexes:(NSIndexSet *)indexes
{
	[self.images removeObjectsAtIndexes:indexes];
}

// -------------------------------------------------------------------------
//  moveItemsAtIndexes:indexes:destinationIndex:
//
//  The user wants to reorder images, update our datasource and the browser will reflect our changes.
// -------------------------------------------------------------------------
- (BOOL)imageBrowser:(IKImageBrowserView *)view moveItemsAtIndexes:(NSIndexSet *)indexes toIndex:(NSUInteger)destinationIndex
{
      NSMutableArray *temporaryArray = [[NSMutableArray alloc] init];
      
	  // first remove items from the datasource and keep them in a temporary array
      for (NSUInteger index = indexes.lastIndex; index != NSNotFound; index = [indexes indexLessThanIndex:index])
      {
          if (index < destinationIndex)
          {
              destinationIndex --;
          }
          
          id obj = self.images[index];
          [temporaryArray addObject:obj];
          [self.images removeObjectAtIndex:index];
      }
  
	  // then insert removed items at the good location
      for (NSUInteger index = 0; index < temporaryArray.count; index++)
      {
          [self.images insertObject:temporaryArray[index] atIndex:destinationIndex];
      }
	
      return YES;
}


#pragma mark - Drag and Drop

// -------------------------------------------------------------------------
//	draggingEntered:sender
//
//  Accept any kind of drop.
// -------------------------------------------------------------------------
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    return NSDragOperationCopy;
}

// -------------------------------------------------------------------------
//	draggingUpdated:sender
// -------------------------------------------------------------------------
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return NSDragOperationCopy;
}

// -------------------------------------------------------------------------
//	performDragOperation:sender
// -------------------------------------------------------------------------
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSData *data = nil;
    NSPasteboard *pasteboard = [sender draggingPasteboard];

	// look for paths in pasteboard
    if ([pasteboard.types containsObject:NSFilenamesPboardType])
    {
        data = [pasteboard dataForType:NSFilenamesPboardType];
    }
    
    if (data != nil)
    {
		// retrieves paths
        NSError *error;
        NSArray *filenames =
            [NSPropertyListSerialization propertyListWithData:data options:kCFPropertyListImmutable format:nil error:&error];

		// add these file paths to our data source as URLs
        for (NSString *filePath in filenames)
        {
            [self addAnImageWithPath:[NSURL fileURLWithPath:filePath]];
        }
		
		// make the image browser reload our datasource
        [self updateDatasource];
    }

	// we accepted the drag operation
	return YES;
}

@end
