/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - GPL
  
  See http://homepage.mac.com/rossetantoine/osirix/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/


/***************************************** Modifications *********************************************

Version 2.3

	20051217	DDP	Added support for page up and page down to decrement or increment the image.
	20060110	DDP	Reducing the variable duplication of userDefault objects (work in progress).
	20060114	Changed off Fullscren to offFullScreen.
	20060119	SUV
*/


#import <DCMView.h>
#import "StringTexture.h"
#import <DCMPix.h>
#import "ROI.h"
#import "NSFont_OpenGL.h"
#import "DCMCursor.h"
#include <Accelerate/Accelerate.h>

#import "ViewerController.h"
#import "MPRController.h"
#import "ThickSlabController.h"
#import "browserController.h"
#import "AppController.h"
#import "MPR2DController.h"
#import "MPR2DView.h"
#import "OrthogonalMPRView.h"
#import "OrthogonalMPRController.h"
#import "ROIWindow.h"
#import "ToolbarPanel.h"

#include <QuickTime/ImageCompression.h> // for image loading and decompression
#include <QuickTime/QuickTimeComponents.h> // for file type support

#include <OpenGL/CGLCurrent.h>
#include <OpenGL/CGLContext.h>
//#include <OpenGL/gl.h> // for OpenGL API
//#include <OpenGL/glext.h> // for OpenGL extension support 

#include "NSFont_OpenGL/NSFont_OpenGL.h"

@class OrthogonalMPRPETCTView;

#define BS 10.

//#define TEXTRECTMODE GL_TEXTURE_2D
//GL_TEXTURE_2D
//#define RECTANGLE false
//GL_TEXTURE_RECTANGLE_EXT - GL_TEXTURE_2D

enum { syncroOFF = 0, syncroABS = 1, syncroREL = 2, syncroLOC = 3, syncroPoint3D = 5};

extern		NSThread					*mainThread;
extern		BOOL						USETOOLBARPANEL;
extern		ToolbarPanelController		*toolbarPanel[10];
extern      BrowserController			*browserWindow;
extern		AppController				*appController;
static      short						syncro = syncroLOC;
static		float						deg2rad = 3.14159265358979/180.0; 
extern		long						numberOf2DViewer;
			BOOL						ALWAYSSYNC = NO, display2DMPRLines = YES;

static		unsigned char				*PETredTable = 0L, *PETgreenTable = 0L, *PETblueTable = 0L;

static		BOOL						pluginOverridesMouse = NO;  // Allows plugins to override mouse click actions.

static		NSString					*pasteBoardOsiriX = @"OsiriX pasteboard";

#define CROSS(dest,v1,v2) \
          dest[0]=v1[1]*v2[2]-v1[2]*v2[1]; \
          dest[1]=v1[2]*v2[0]-v1[0]*v2[2]; \
          dest[2]=v1[0]*v2[1]-v1[1]*v2[0];
		  
#define DOT(v1,v2) (v1[0]*v2[0]+v1[1]*v2[1]+v1[2]*v2[2])

#define SUB(dest,v1,v2) dest[0]=v1[0]-v2[0]; \
						dest[1]=v1[1]-v2[1]; \
						dest[2]=v1[2]-v2[2]; 
		  
short intersect3D_2Planes( float *Pn1, float *Pv1, float *Pn2, float *Pv2, float *u, float *iP)
{
	CROSS(u, Pn1, Pn2);         // cross product -> perpendicular vector
	
	float    ax = (u[0] >= 0 ? u[0] : -u[0]);
    float    ay = (u[1] >= 0 ? u[1] : -u[1]);
    float    az = (u[2] >= 0 ? u[2] : -u[2]);
	
    // test if the two planes are parallel
    if ((ax+ay+az) < 0.01)
	{   // Pn1 and Pn2 are near parallel
        // test if disjoint or coincide
        //Vector   v = Pn2.V0 - Pn1.V0;

        //if (dot(Pn1.n, v) == 0)         // Pn2.V0 lies in Pn1
        //    return -2;                   // Pn1 and Pn2 coincide
        //else 
            return -1;                   // Pn1 and Pn2 are disjoint
    }
	
    // Pn1 and Pn2 intersect in a line
    // first determine max abs coordinate of cross product
    int      maxc;                      // max coordinate
    if (ax > ay) {
        if (ax > az)
             maxc = 1;
        else maxc = 3;
    }
    else {
        if (ay > az)
             maxc = 2;
        else maxc = 3;
    }
	
    // next, to get a point on the intersect line
    // zero the max coord, and solve for the other two
	
    float    d1, d2;            // the constants in the 2 plane equations
    d1 = -DOT(Pn1, Pv1); 		// note: could be pre-stored with plane
    d2 = -DOT(Pn2, Pv2); 		// ditto
	
    switch (maxc) {            // select max coordinate
    case 1:                    // intersect with x=0
        iP[0] = 0;
        iP[1] = (d2*Pn1[2] - d1*Pn2[2]) / u[0];
        iP[2] = (d1*Pn2[1] - d2*Pn1[1]) / u[0];
        break;
    case 2:                    // intersect with y=0
        iP[0] = (d1*Pn2[2] - d2*Pn1[2]) / u[1];
        iP[1] = 0;
        iP[2] = (d2*Pn1[0] - d1*Pn2[0]) / u[1];
        break;
    case 3:                    // intersect with z=0
        iP[0] = (d2*Pn1[1] - d1*Pn2[1]) / u[2];
        iP[1] = (d1*Pn2[0] - d2*Pn1[0]) / u[2];
        iP[2] = 0;
    }
    return noErr;
}


// ---------------------------------
/*
static void DrawGLTexelGrid (float textureWidth, float textureHeight, float imageWidth, float imageHeight, float zoom) // in pixels
{
    long i; // iterator
    float perpenCoord, coord, coordStep; //  perpendicular coordinate, dawing (iteratoring) coordinate, coordiante step amount per line
	
	glBegin (GL_LINES); // draw using lines
		// vertical lines
		perpenCoord = 0.5f * imageHeight * zoom; // 1/2 height of image in world space
		coord =  -0.5f * imageWidth * zoom; // starting scaled coordinate for half of image width (world space)
		coordStep = imageWidth / textureWidth * zoom; // space between each line (maps texture size to image size)
		for (i = 0; i <= textureWidth; i++) // ith column
		{
			glVertex3f (coord, -perpenCoord, 0.0f); // draw from current column, top of image to...
			glVertex3f (coord, perpenCoord, 0.0f); // current column, bottom of image
			coord += coordStep; // step to next column
		}
		// horizontal lines
		perpenCoord = 0.5f * imageWidth * zoom; // 1/2 width of image in world space
    	coord =  -0.5f * imageHeight * zoom; // scaled coordinate for half of image height (actual drawing coords)
		coordStep = imageHeight / textureHeight * zoom; // space between each line (maps texture size to image size)
		for (i = 0; i <= textureHeight; i++) // ith row
		{
			glVertex3f (-perpenCoord, coord, 0.0f); // draw from current row, left edge of image to...
			glVertex3f (perpenCoord, coord, 0.0f);// current row, right edge of image
			coord += coordStep; // step to next row
		}
	glEnd(); // end our set of lines
}*/

static void DrawGLImageTile (unsigned long drawType, float imageWidth, float imageHeight, float zoom, float textureWidth, float textureHeight,
                            float offsetX, float offsetY, float endX, float endY, Boolean texturesOverlap, Boolean textureRectangle)
{
	float startXDraw = (offsetX - imageWidth * 0.5f) * zoom; // left edge of poly: offset is in image local coordinates convert to world coordinates
	float endXDraw = (endX - imageWidth * 0.5f) * zoom; // right edge of poly: offset is in image local coordinates convert to world coordinates
	float startYDraw = (offsetY - imageHeight * 0.5f) * zoom; // top edge of poly: offset is in image local coordinates convert to world coordinates
	float endYDraw = (endY - imageHeight * 0.5f) * zoom; // bottom edge of poly: offset is in image local coordinates convert to world coordinates
	float texOverlap =  texturesOverlap ? 1.0f : 0.0f; // size of texture overlap, switch based on whether we are using overlap or not
	float startXTexCoord = texOverlap / (textureWidth + 2.0f * texOverlap); // texture right edge coordinate (stepped in one pixel for border if required)
	float endXTexCoord = 1.0f - startXTexCoord; // texture left edge coordinate (stepped in one pixel for border if required)
	float startYTexCoord = texOverlap / (textureHeight + 2.0f * texOverlap); // texture top edge coordinate (stepped in one pixel for border if required)
	float endYTexCoord = 1.0f - startYTexCoord; // texture bottom edge coordinate (stepped in one pixel for border if required)
	if (textureRectangle)
	{
		startXTexCoord = texOverlap; // texture right edge coordinate (stepped in one pixel for border if required)
		endXTexCoord = textureWidth + texOverlap; // texture left edge coordinate (stepped in one pixel for border if required)
		startYTexCoord = texOverlap; // texture top edge coordinate (stepped in one pixel for border if required)
		endYTexCoord = textureHeight + texOverlap; // texture bottom edge coordinate (stepped in one pixel for border if required)
	}
	if (endX > (imageWidth + 0.5)) // handle odd image sizes, (+0.5 is to ensure there is no fp resolution problem in comparing two fp numbers)
	{
		endXDraw = (imageWidth * 0.5f) * zoom; // end should never be past end of image, so set it there
		if (textureRectangle)
			endXTexCoord -= 1.0f;
		else
			endXTexCoord = 1.0f -  2.0f * startXTexCoord; // for the last texture in odd size images there are two texels of padding so step in 2
	}
	if (endY > (imageHeight + 0.5f)) // handle odd image sizes, (+0.5 is to ensure there is no fp resolution problem in comparing two fp numbers)
	{
		endYDraw = (imageHeight * 0.5f) * zoom; // end should never be past end of image, so set it there
		if (textureRectangle)
			endYTexCoord -= 1.0f;
		else
			endYTexCoord = 1.0f -  2.0f * startYTexCoord; // for the last texture in odd size images there are two texels of padding so step in 2
	}
	
	glBegin (drawType); // draw either tri strips of line strips (so this will drw either two tris or 3 lines)
		glTexCoord2f (startXTexCoord, startYTexCoord); // draw upper left in world coordinates
		glVertex3d (startXDraw, startYDraw, 0.0);

		glTexCoord2f (endXTexCoord, startYTexCoord); // draw lower left in world coordinates
		glVertex3d (endXDraw, startYDraw, 0.0);

		glTexCoord2f (startXTexCoord, endYTexCoord); // draw upper right in world coordinates
		glVertex3d (startXDraw, endYDraw, 0.0);

		glTexCoord2f (endXTexCoord, endYTexCoord); // draw lower right in world coordinates
		glVertex3d (endXDraw, endYDraw, 0.0);
	glEnd();
	
	// finish strips
/*	if (drawType == GL_LINE_STRIP) // draw top and bottom lines which were not draw with above
	{
		glBegin (GL_LINES);
			glVertex3d(startXDraw, endYDraw, 0.0); // top edge
			glVertex3d(startXDraw, startYDraw, 0.0);
	
			glVertex3d(endXDraw, startYDraw, 0.0); // bottom edge
			glVertex3d(endXDraw, endYDraw, 0.0);
		glEnd();
	}*/
}


static long GetNextTextureSize (long textureDimension, long maxTextureSize, Boolean textureRectangle)
{
	long targetTextureSize = maxTextureSize; // start at max texture size
	if (textureRectangle)
	{
		if (textureDimension >= targetTextureSize) // the texture dimension is greater than the target texture size (i.e., it fits)
			return targetTextureSize; // return corresponding texture size
		else
			return textureDimension; // jusr return the dimension
	}
	else
	{
		do // while we have txture sizes check for texture value being equal or greater
		{  
			if (textureDimension >= targetTextureSize) // the texture dimension is greater than the target texture size (i.e., it fits)
				return targetTextureSize; // return corresponding texture size
		}
		while (targetTextureSize >>= 1); // step down to next texture size smaller
	}
	return 0; // no textures fit so return zero
}

static long GetTextureNumFromTextureDim (long textureDimension, long maxTextureSize, Boolean texturesOverlap, Boolean textureRectangle) 
{
	// start at max texture size 
	// loop through each texture size, removing textures in turn which are less than the remaining texture dimension
	// each texture has 2 pixels of overlap (one on each side) thus effective texture removed is 2 less than texture size
	
	long i = 0; // initially no textures
	long bitValue = maxTextureSize; // start at max texture size
	long texOverlapx2 = texturesOverlap ? 2 : 0;
	textureDimension -= texOverlapx2; // ignore texture border since we are using effective texure size (by subtracting 2 from the initial size)
	if (textureRectangle)
	{
		// count number of full textures
		while (textureDimension > (bitValue - texOverlapx2)) // while our texture dimension is greater than effective texture size (i.e., minus the border)
		{
			i++; // count a texture
			textureDimension -= bitValue - texOverlapx2; // remove effective texture size
		}
		// add one partial texture
		i++; 
	}
	else
	{
		do
		{
			while (textureDimension >= (bitValue - texOverlapx2)) // while our texture dimension is greater than effective texture size (i.e., minus the border)
			{
				i++; // count a texture
				textureDimension -= bitValue - texOverlapx2; // remove effective texture size
			}
		}
		while ((bitValue >>= 1) > texOverlapx2); // step down to next texture while we are greater than two (less than 4 can't be used due to 2 pixel overlap)
	if (textureDimension > 0x0) // if any textureDimension is left there is an error, because we can't texture these small segments and in anycase should not have image pixels left
		NSLog (@"GetTextureNumFromTextureDim error: Texture to small to draw, should not ever get here, texture size remaining");
	}
	return i; // return textures counted
} 

@implementation DCMView

- (void) erase2DPointMarker
{
	display2DPoint = NSMakePoint(0,0);
}

- (void) draw2DPointMarker
{
	if( display2DPoint.x != 0 || display2DPoint.y != 0)
	{
		glColor3f (0.0f, 0.5f, 1.0f);
		glLineWidth(2.0);
		glBegin(GL_LINES);
		
		float crossx, crossy;
		
		crossx = display2DPoint.x - [curDCM pwidth]/2.;
		crossy = display2DPoint.y - [curDCM pheight]/2.;
		
		glVertex2f( scaleValue * (crossx - 40), scaleValue*(crossy));
		glVertex2f( scaleValue * (crossx - 5), scaleValue*(crossy));
		glVertex2f( scaleValue * (crossx + 40), scaleValue*(crossy));
		glVertex2f( scaleValue * (crossx + 5), scaleValue*(crossy));
		
		glVertex2f( scaleValue * (crossx), scaleValue*(crossy-40));
		glVertex2f( scaleValue * (crossx), scaleValue*(crossy-5));
		glVertex2f( scaleValue * (crossx), scaleValue*(crossy+5));
		glVertex2f( scaleValue * (crossx), scaleValue*(crossy+40));
		glEnd();
	}
}

- (void) Display3DPoint:(NSNotification*) note
{
	if( stringID == 0L)
	{
		NSMutableArray	*v = [note object];
		
		if( v == dcmPixList)
		{
			display2DPoint.x = [[[note userInfo] valueForKey:@"x"] intValue];
			display2DPoint.y = [[[note userInfo] valueForKey:@"y"] intValue];
			[self setNeedsDisplay: YES];
		}
	}
}

-(OrthogonalMPRController*) controller
{
	return 0L;	// Only defined in herited classes
}

- (void) stopROIEditing
{
	long i, x, no;
	
	drawingROI = NO;
	for( i = 0; i < [curRoiList count]; i++)
	{
		if( curROI != [curRoiList objectAtIndex:i])
		{
			if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selectedModify || [[curRoiList objectAtIndex:i] ROImode] == ROI_drawing)
			{
				ROI	*roi = [curRoiList objectAtIndex:i];
				[roi setROIMode: ROI_selected];
			}
		}
	}
	
	if( curROI)
	{
		if( [curROI ROImode] == ROI_selectedModify || [curROI ROImode] == ROI_drawing)
		{
			// Does this ROI have alias in other views?
			for( x = 0, no = 0; x < [dcmRoiList count]; x++)
			{
				if( [[dcmRoiList objectAtIndex: x] containsObject: curROI]) no++;
			}
		
			if( no <= 1)
			{
				[curROI setROIMode: ROI_sleep];
				curROI = 0L;
			}
		}
		else
		{
			[curROI setROIMode: ROI_sleep];
			curROI = 0L;
		}
	}
}

- (void) blendingPropagate
{
//	if([stringID isEqualToString:@"OrthogonalMPRVIEW"] && blendingView)
//	{
//		[[self controller] blendingPropagate: self];
//	}
//	else 
	if( blendingView)
	{
		if( [stringID isEqualToString:@"Original"])
		{
			float fValue = [self scaleValue] / [self pixelSpacing];
			[blendingView setScaleValue: fValue * [blendingView pixelSpacing]];
		}
		else [blendingView setScaleValue: scaleValue];
		
		[blendingView setRotation: rotation];
		[blendingView setOrigin: origin];
		[blendingView setOriginOffset: originOffset];
	}
}

- (IBAction) alwaysSyncMenu:(id) sender
{
	ALWAYSSYNC = !ALWAYSSYNC;
	
	[sender setState:!ALWAYSSYNC];
}

- (IBAction) roiLoadFromFiles: (id) sender
{
    long    i, j, x, result;
    
    NSOpenPanel         *oPanel = [NSOpenPanel openPanel];
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setCanChooseDirectories:NO];
    
    result = [oPanel runModalForDirectory:0L file:nil types:[NSArray arrayWithObject:@"roi"]];
    
    if (result == NSOKButton) 
    {
        // Unselect all ROIs
        for( i = 0 ; i < [curRoiList count] ; i++) [[curRoiList objectAtIndex: i] setROIMode: ROI_sleep];
        
        for( i = 0; i < [[oPanel filenames] count]; i++)
        {
            NSMutableArray*    roiArray = [NSUnarchiver unarchiveObjectWithFile: [[oPanel filenames] objectAtIndex:i]];

            for( j = 0 ; j < [roiArray count] ; j++)
            {
                [[roiArray objectAtIndex: j] setOriginAndSpacing:[curDCM pixelSpacingX] :[curDCM pixelSpacingY] :NSMakePoint( [curDCM originX], [curDCM originY])];
                [[roiArray objectAtIndex: j] setROIMode: ROI_selected];
                [[roiArray objectAtIndex: j] setRoiFont: labelFontListGL :labelFontListGLSize :self];
                
                [[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: [roiArray objectAtIndex: j] userInfo: nil];
            }
            
            [curRoiList addObjectsFromArray: roiArray];
        }
        
        [self setNeedsDisplay:YES];
    }
}

- (IBAction) roiSaveSelected: (id) sender
{
	NSSavePanel     *panel = [NSSavePanel savePanel];
    short           i;
	
	NSMutableArray  *selectedROIs = [NSMutableArray  arrayWithCapacity:0];
	
	for( i = 0; i < [curRoiList count]; i++)
	{
		if( [[curRoiList objectAtIndex: i] ROImode] == ROI_selected)
		{
			[selectedROIs addObject: [curRoiList objectAtIndex: i]];
		}
	}
	
	if( [selectedROIs count] > 0)
	{
		[panel setCanSelectHiddenExtension:NO];
		[panel setRequiredFileType:@"roi"];
		
		if( [panel runModalForDirectory:0L file:[[selectedROIs objectAtIndex:0] name]] == NSFileHandlingPanelOKButton)
		{
			[NSArchiver archiveRootObject: selectedROIs toFile :[panel filename]];
		}
	}
	else
	{
		NSRunCriticalAlertPanel(NSLocalizedString(@"ROIs Save Error",nil), NSLocalizedString(@"No ROI(s) selected to save!",nil) , NSLocalizedString(@"OK",nil), nil, nil);
	}
}

- (IBAction) roiLoadFromXMLFiles: (id) sender
{
	long	i, x, result;
	
	NSOpenPanel         *oPanel = [NSOpenPanel openPanel];
	
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setCanChooseDirectories:NO];
	
	result = [oPanel runModalForDirectory:0L file:nil types:[NSArray arrayWithObject:@"xml"]];
    
    if (result != NSOKButton) return;
	
	// Unselect all ROIs
	for( i = 0 ; i < [curRoiList count] ; i++) [[curRoiList objectAtIndex: i] setROIMode: ROI_sleep];
	
	for( i = 0; i < [[oPanel filenames] count]; i++)
	{
		NSDictionary*	xml = [NSDictionary dictionaryWithContentsOfFile: [[oPanel filenames] objectAtIndex:i]];
		NSArray*		roiArray = [xml objectForKey: @"ROI array"];
		
		if ( roiArray ) {
			int j;
			for ( j = 0; j < [roiArray count]; j++ ) {
				NSDictionary *roiDict = [roiArray objectAtIndex: j];
				
				int sliceIndex = [[roiDict objectForKey: @"Slice"] intValue] - 1;
				
				NSMutableArray *roiList = [dcmRoiList objectAtIndex: sliceIndex];
				DCMPix *dcm = [dcmPixList objectAtIndex: sliceIndex];
				
				if ( roiList == nil || dcm == nil ) continue;  // No such slice.  Can't add ROI.
				
				ROI *roi = [[ROI alloc] initWithType: tCPolygon :[dcm pixelSpacingX] :[dcm pixelSpacingY] :NSMakePoint( [dcm originX], [dcm originY])];
				[roi setName: [xml objectForKey: @"Name"]];
				[roi setComments: [roiDict objectForKey: @"Comments"]];
				
				NSArray *pointsStringArray = [roiDict objectForKey: @"ROIPoints"];
				NSMutableArray *pointsArray = [NSMutableArray arrayWithCapacity: 0];
				
				int k;
				for ( k = 0; k < [pointsStringArray count]; k++ ) {
					MyPoint *pt = [MyPoint point: NSPointFromString( [pointsStringArray objectAtIndex: k] )];
					[pointsArray addObject: pt];
				}
				
				[roi setPoints: pointsArray];
				[roi setRoiFont: labelFontListGL :labelFontListGLSize :self];
				
				[roiList addObject: roi];
				
				[roi release];
								
			}
		}
		
		else {  // Single ROI - assume current slice
			ROI *roi = [[ROI alloc] initWithType: tCPolygon :[curDCM pixelSpacingX] :[curDCM pixelSpacingY] :NSMakePoint( [curDCM originX], [curDCM originY])];
			[roi setName: [xml objectForKey: @"Name"]];
			[roi setComments: [xml objectForKey: @"Comments"]];
			
			NSArray *pointsStringArray = [xml objectForKey: @"ROIPoints"];
			NSMutableArray *pointsArray = [NSMutableArray arrayWithCapacity: 0];
			
			if( [pointsStringArray count] > 0)
			{
				int j;
				for ( j = 0; j < [pointsStringArray count]; j++ ) {
					MyPoint *pt = [MyPoint point: NSPointFromString( [pointsStringArray objectAtIndex: j] )];
					[pointsArray addObject: pt];
				}
				
				[roi setPoints: pointsArray];
				[roi setROIMode: ROI_selected];
				[roi setRoiFont: labelFontListGL :labelFontListGLSize :self];
				
				[curRoiList addObject: roi];
				[[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: roi userInfo: nil];
			}
			
			[roi release];
		}
	}
	
	[self setNeedsDisplay:YES];
}

- (void)paste:(id)sender
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *archived_data = [pb dataForType:@"ROIObject"];
	
	if( archived_data)
	{
		long	i;
		NSMutableArray*	roiArray = [NSUnarchiver unarchiveObjectWithData: archived_data];
		
		// Unselect all ROIs
		for( i = 0 ; i < [curRoiList count] ; i++) [[curRoiList objectAtIndex: i] setROIMode: ROI_sleep];
		
		for( i = 0 ; i < [roiArray count] ; i++)
		{
			[[roiArray objectAtIndex: i] setOriginAndSpacing:[curDCM pixelSpacingX] :[curDCM pixelSpacingY] :NSMakePoint( [curDCM originX], [curDCM originY])];
			[[roiArray objectAtIndex: i] setROIMode: ROI_selected];
			[[roiArray objectAtIndex: i] setRoiFont: labelFontListGL :labelFontListGLSize :self];
		}
		
		[curRoiList addObjectsFromArray: roiArray];
		
		for( i = 0 ; i < [roiArray count] ; i++)
			[[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: [roiArray objectAtIndex: i] userInfo: nil];

		[self setNeedsDisplay:YES];
	}
}

-(IBAction) copy:(id) sender
{
    NSPasteboard	*pb = [NSPasteboard generalPasteboard];
	BOOL			roiSelected = NO;
	long			i;
	NSMutableArray  *roiSelectedArray = [NSMutableArray arrayWithCapacity:0];
	
	for( i = 0; i < [curRoiList count]; i++)
	{
		if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)
		{
			roiSelected = YES;
			
			[roiSelectedArray addObject: [curRoiList objectAtIndex:i]];
		}
	}

	if( roiSelected == NO)
	{
		NSImage *im;
		
		[pb declareTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:self];
		
		im = [self nsimage: [[NSUserDefaults standardUserDefaults] boolForKey: @"ORIGINALSIZE"]];
		
		[pb setData: [im TIFFRepresentation] forType:NSTIFFPboardType];
		
		[im release];
	}
	else
	{
		[pb declareTypes:[NSArray arrayWithObjects:@"ROIObject", nil] owner:nil];
		[pb setData: [NSArchiver archivedDataWithRootObject: roiSelectedArray] forType:@"ROIObject"];
	}
}

-(IBAction) cut:(id) sender
{
	[self copy:sender];
	
	long	i;
	BOOL	done = NO;
	
	for( i = 0; i < [curRoiList count]; i++)
	{
		if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)
		{
			[[NSNotificationCenter defaultCenter] postNotificationName: @"removeROI" object:[curRoiList objectAtIndex:i] userInfo: 0L];
			[curRoiList removeObjectAtIndex:i];
			i--;
		}
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName: @"roiRemovedFromArray" object: 0L userInfo: 0L];
	
	[self setNeedsDisplay:YES];
}

- (IBAction)saveDocumentAs:(id)sender
{
	#if !__LP64__
   	NSImage *im;	
	im = [self nsimage: [[NSUserDefaults standardUserDefaults] boolForKey: @"ORIGINALSIZE"]];		
    NSFileManager *manager = [NSFileManager defaultManager]; 
    GraphicsImportComponent	graphicsImporter;
    Boolean 	gotFSRef = false;
    FSRef 	fileFSRef;
    OSStatus 	status;
    FSSpec 	fileFSSpec;
   // FSSpec 	fileNameFSSpec;
    OSErr 	err;
    ComponentResult result;
    //NSString 	*filePath = @"/tmp/iRad.tif";
    NSString 	*filePath = [[NSDate date] description];
    NSURL 	*fileUrl = [NSURL fileURLWithPath:filePath];
    //if ([manager fileExistsAtPath:filePath])
    //    [manager removeFileAtPath:filePath handler:nil];

    [[im TIFFRepresentation] writeToFile:filePath atomically:YES];

           // create Quicktime Importer
   // fileNameFSSpec.name = [[[[myDoc keyView] dicomObject] objectWithDescription:@"PatientsName"] UTF8String];
            
    // get an FSRef for our file
    gotFSRef = CFURLGetFSRef((CFURLRef)fileUrl, &fileFSRef);
    
    // get an FSSpec for the same file, which we can
    // pass to GetGraphicsImporterForFile below
    status = FSGetCatalogInfo(&fileFSRef, kFSCatInfoNone, 
            NULL, NULL, &fileFSSpec, NULL);
    
    // find a graphics importer for our image file
    err = GetGraphicsImporterForFile(&fileFSSpec, &graphicsImporter);
            
    
    result = GraphicsImportDoExportImageFileDialog ( graphicsImporter,
                                                    NULL,
                                                    NULL,
                                                    NULL,
                                                    NULL,
                                                    NULL,
                                                    NULL);


  [manager removeFileAtPath:filePath handler:nil];
  [im release];
  #endif
}

-(BOOL)yFlipped{
	return yFlipped;
}

- (void) setYFlipped:(BOOL) v {
	yFlipped = v;
	[[self seriesObj]  setValue:[NSNumber numberWithBool:yFlipped] forKey:@"yFlipped"];
//	NSLog( @"Vertical" );
	[appController setYFlipped: yFlipped];	
    [self setNeedsDisplay:YES];
}

-(BOOL)xFlipped{
	return xFlipped;
}

- (void) setXFlipped:(BOOL) v {
	xFlipped = v;
	[[self seriesObj]  setValue:[NSNumber numberWithBool:xFlipped] forKey:@"xFlipped"];
//	NSLog( @"Horizontal" );
	[appController setXFlipped: xFlipped];
    [self setNeedsDisplay:YES];
}

- (void)flipVertical: (id)sender {
	[self setYFlipped: !yFlipped];
}

- (void)flipHorizontal: (id)sender {
	[self setXFlipped: !xFlipped];
}

- (long) lengthOfString:( char *) cstr forFont:(long *)fontSizeArray
{
	long i = 0, temp = 0;
	
	while( cstr[ i] != 0)
	{
		temp += fontSizeArray[ cstr[ i]];
		i++;
	}
	return temp;
}

- (NSSize)sizeOfString:(NSString *)string forFont:(NSFont *)font
{
	NSDictionary *attr = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
	NSAttributedString *attrString = [[[NSAttributedString alloc] initWithString:string attributes:attr] autorelease];
	return [attrString size];
}

- (void) DrawNSStringGL: (NSString*) str :(GLuint) fontL :(long) x :(long) y rightAlignment: (BOOL) right useStringTexture: (BOOL) stringTex
{
	if( stringTex)
	{
		if( stringTextureCache == 0L) stringTextureCache = [[NSMutableDictionary alloc] initWithCapacity: 0];
		
		StringTexture *stringTex = [stringTextureCache objectForKey: str];
		if( stringTex == 0L)
		{
			if( [stringTextureCache count] > 100) [stringTextureCache removeAllObjects];
			
			NSMutableDictionary *stanStringAttrib = [NSMutableDictionary dictionary];
			
			if( fontL == labelFontListGL) [stanStringAttrib setObject:labelFont forKey:NSFontAttributeName];
			else [stanStringAttrib setObject:fontGL forKey:NSFontAttributeName];
			[stanStringAttrib setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];

			stringTex = [[StringTexture alloc] initWithString:str withAttributes:stanStringAttrib];
			[stringTex genTexture];
			[stringTextureCache setObject:stringTex forKey:str];
			[stringTex release];
		}
		
		if( right) x -= [stringTex texSize].width;
		else x -= 5;
		
		glEnable (GL_TEXTURE_RECTANGLE_EXT);
		glEnable(GL_BLEND);
		glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		
		long xc, yc;
		xc = x+2;
		yc = y+1-[stringTex texSize].height;
		glColor4f (0.0f, 0.0f, 0.0f, 1.0f);
		[stringTex drawAtPoint:NSMakePoint( xc+1, yc+1)];
		
		glColor4f (1.0f, 1.0f, 1.0f, 1.0f);
		[stringTex drawAtPoint:NSMakePoint( xc, yc)];
		
		glDisable(GL_BLEND);
		glDisable (GL_TEXTURE_RECTANGLE_EXT);
	}
	else
	{
		char	*cstrOut = (char*) [str UTF8String];
		if( right)
		{
			if( fontL == labelFontListGL) x -= [self lengthOfString:cstrOut forFont:labelFontListGLSize] + 2;
			else x -= [self lengthOfString:cstrOut forFont:fontListGLSize] + 2;
		}
		unsigned char	*lstr = (unsigned char*) cstrOut;
		
		if (fontColor)
			glColor4f([fontColor redComponent], [fontColor greenComponent], [fontColor blueComponent], [fontColor alphaComponent]);
		else
			glColor4f (0.0, 0.0, 0.0, 1.0);

		glRasterPos3d (x+1, y+1, 0);
		
		GLint i = 0;
		while (lstr [i])
		{
			long val = lstr[i++] - ' ';
			if( val < 150 && val >= 0) glCallList (fontL+val);
		}
		
		glColor4f (1.0f, 1.0f, 1.0f, 1.0f);
		
		glRasterPos3d (x, y, 0);
		
		i = 0;
		while (lstr [i])
		{
			long val = lstr[i++] - ' ';
			if( val < 150 && val >= 0) glCallList (fontL+val);
		}
	}
}

- (void) DrawCStringGL: ( char *) cstrOut :(GLuint) fontL :(long) x :(long) y rightAlignment: (BOOL) right useStringTexture: (BOOL) stringTex
{
	[self DrawNSStringGL: [NSString stringWithCString: cstrOut] :(GLuint) fontL :(long) x :(long) y rightAlignment: (BOOL) right useStringTexture: (BOOL) stringTex];
}

- (void) DrawCStringGL: (char *) cstrOut :(GLuint) fontL :(long) x :(long) y
{
	[self DrawCStringGL: (char *) cstrOut :(GLuint) fontL :(long) x :(long) y rightAlignment: NO useStringTexture: NO];
}

- (void) DrawNSStringGL: (NSString*) cstrOut :(GLuint) fontL :(long) x :(long) y
{
	[self DrawNSStringGL: (NSString*) cstrOut :(GLuint) fontL :(long) x :(long) y rightAlignment: NO useStringTexture: NO];
}

- (short) currentTool {return currentTool;}
- (short) currentToolRight  {return currentToolRight;}

-(void) setRightTool:(short) i
{
	currentToolRight = i;
	
	[[NSUserDefaults standardUserDefaults] setInteger:currentToolRight forKey: @"DEFAULTRIGHTTOOL"];
}

-(void) setCurrentTool:(short) i
{
    currentTool = i;
    
	[self stopROIEditing];
	
    mesureA.x = mesureA.y = mesureB.x = mesureB.y = 0;
    roiRect.origin.x = roiRect.origin.y = roiRect.size.width = roiRect.size.height = 0;
	
	// Unselect previous ROIs
	for( i = 0; i < [curRoiList count]; i++) [[curRoiList objectAtIndex: i] setROIMode : ROI_sleep];
	
	NSEvent *event = [[NSApplication sharedApplication] currentEvent];
	
	switch( currentTool)
	{
		case tPlain:
			if ([[[self window] windowController] is2DViewer] == YES)
			{
				[[[self window] windowController] brushTool: self];
			}
		break;
		
		case tZoom:
			if( [event type] != NSKeyDown)
			{
				if( [event clickCount] == 2)
				{
					origin.x = origin.y = 0;
					rotation = 0;
					[self scaleToFit];
					
					//set value for Series Object Presentation State
					if ([[[self window] windowController] is2DViewer] == YES)
					{
						[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.x] forKey:@"xOffset"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.y] forKey:@"yOffset"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:rotation] forKey:@"rotationAngle"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:0] forKey:@"displayStyle"]; 
						[[self seriesObj] setValue:[NSNumber numberWithFloat:scaleValue] forKey:@"scale"];
					}
				}
				
				if( [event clickCount] == 3)
				{
					origin.x = origin.y = 0;
					rotation = 0;
					scaleValue = 1;
					if ([[[self window] windowController] is2DViewer] == YES)
					{
						[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.x] forKey:@"xOffset"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.y] forKey:@"yOffset"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:scaleValue] forKey:@"scale"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:rotation] forKey:@"rotationAngle"];
						[[self seriesObj] setValue:[NSNumber numberWithFloat:1] forKey:@"displayStyle"];
					}
				}
			}
		break;
		
		case tRotate:
			if( [event type] != NSKeyDown)
			{
				if( [event clickCount] == 2)
				{
					rotation += 90;
				}
				
				if( [event clickCount] == 3)
				{
					rotation += 180;
				}
				[[self seriesObj] setValue:[NSNumber numberWithFloat:rotation] forKey:@"rotationAngle"];
			}
		break;
	}
	
	[self setCursorForView : currentTool];
	[self setNeedsDisplay:YES];
}

-(void) checkVisible
{
    float newYY, newXX, xx, yy;
    
    xx = origin.x*cos(rotation*deg2rad) + origin.y*sin(rotation*deg2rad);
    yy = origin.x*sin(rotation*deg2rad) - origin.y*cos(rotation*deg2rad);

    NSRect size = [self bounds];
    if( scaleValue > 1.0)
    {
        size.size.width = [curDCM pwidth]*scaleValue;
        size.size.height = [curDCM pheight]*scaleValue;
    }
    
    if( xx*scaleValue < -size.size.width/2) newXX = (-size.size.width/2.0/scaleValue);
    else if( xx*scaleValue > size.size.width/2) newXX = (size.size.width/2.0/scaleValue);
    else newXX = xx;
    
    if( yy*scaleValue < -size.size.height/2) newYY = -size.size.height/2.0/scaleValue;
    else  if( yy*scaleValue > size.size.height/2) newYY = size.size.height/2.0/scaleValue;
    else newYY = yy;
    
    origin.x = newXX*cos(rotation*deg2rad) + newYY*sin(rotation*deg2rad);
    origin.y = newXX*sin(rotation*deg2rad) - newYY*cos(rotation*deg2rad);
}

-(void) setTheMatrix:(NSMatrix*) m
{
    matrix = m;
}

- (void) scaleToFit
{
	if ([[[self seriesObj] valueForKey:@"displayStyle"] intValue] == 0 || [[[self window] windowController] is2DViewer] == NO) {
		NSRect  sizeView = [self bounds];
		
		if( sizeView.size.width/[curDCM pwidth] < sizeView.size.height/[curDCM pheight]/[curDCM pixelRatio])
		{
			[self setScaleValue:(sizeView.size.width/[curDCM pwidth])];
	//		scaleValue = sizeView.size.width/[curDCM pwidth];
		}
		else
		{
			[self setScaleValue:(sizeView.size.height/[curDCM pheight]/[curDCM pixelRatio])];
	//		scaleValue = sizeView.size.height/[curDCM pheight]/[curDCM pixelRatio];
		}
	}
	else
		[self setScaleValue: [[[self seriesObj] valueForKey:@"scale"] floatValue]];
	[self setNeedsDisplay:YES];
}

- (void) setIndexWithReset:(short) index :(BOOL) sizeToFit
{
	long i;
	if( dcmPixList && index != -1)
    {
		[[self window] setAcceptsMouseMovedEvents: YES];

		curROI = 0L;
		
		origin.x = origin.y = 0;
		curImage = index; 
		if( curImage >= [dcmPixList count]) curImage = [dcmPixList count] -1;
		curDCM = [dcmPixList objectAtIndex: curImage];
		
		[curRoiList release];
		
		if( dcmRoiList) curRoiList = [[dcmRoiList objectAtIndex: curImage] retain];
		else
		{
			curRoiList = [[NSMutableArray alloc] initWithCapacity:0];
		}
		
		for( i = 0; i < [curRoiList count]; i++)
		{
			[[curRoiList objectAtIndex:i ] setRoiFont: labelFontListGL :labelFontListGLSize :self];
			[[curRoiList objectAtIndex:i ] recompute];
			// Unselect previous ROIs
			[[curRoiList objectAtIndex: i] setROIMode : ROI_sleep];
		}
		
		curWW = [curDCM ww];
		curWL = [curDCM wl];
		
		
		
		rotation = 0;
		
		//get Presentation State info from series Object
		[self updatePresentationStateFromSeries];
		
		[curDCM checkImageAvailble :curWW :curWL];
		
//		NSSize  sizeView = [[self enclosingScrollView] contentSize];
//		[self setFrameSize:sizeView];
		
		NSRect  sizeView = [self bounds];
		if( sizeToFit && [[[self seriesObj] valueForKey:@"displayStyle"] intValue] == 0 || [[[self window] windowController] is2DViewer] == NO) {
			[self scaleToFit];
		}
		
		if( [[[self window] windowController] is2DViewer] == YES)
		{
			if( [curDCM sourceFile])
			{
				if( [[[self window] windowController] is2DViewer] == YES) [[self window] setRepresentedFilename: [curDCM sourceFile]];
			}
		}
		
		[self loadTextures];
		[self setNeedsDisplay:YES];
		
//		if( [[[self window] windowController] is2DViewer] == YES)
//			[[[self window] windowController] propagateSettings];
		
		if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
//		if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];

		[yearOld release];
		yearOld = [[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.yearOld"] retain];
	}
}

- (void) setDCM:(NSMutableArray*) c :(NSArray*)d :(NSMutableArray*)e :(short) firstImage :(char) type :(BOOL) reset
{
	long i;
	
	curDCM = 0L;
    [self setXFlipped: NO];
	[self setYFlipped: NO];
	
	if( dcmPixList != c)
	{
		if( dcmPixList) [dcmPixList release];
		dcmPixList = c;
		[dcmPixList retain];
		volumicSeries = YES;
		if( [stringID isEqualToString:@"previewDatabase"] == NO)
			if( [[dcmPixList objectAtIndex: 0] sliceLocation] == [[dcmPixList objectAtIndex: [dcmPixList count]-1] sliceLocation]) volumicSeries = NO;
    }
	
	if( dcmFilesList != d)
	{
		if( dcmFilesList) [dcmFilesList release];
		dcmFilesList = d;
		[dcmFilesList retain];
	}
	
	flippedData = NO;
	
	if( dcmRoiList != e)
	{
		if( dcmRoiList) [dcmRoiList release];
		dcmRoiList = e;
		[dcmRoiList retain];
    }
	
    listType = type;
    
	if( dcmPixList)
	{
		if( reset == YES) [self setIndexWithReset: firstImage :YES];
	}
	
	//get Presentation State info from series Object
	[self updatePresentationStateFromSeries];
	
    [self setNeedsDisplay:true];
}

- (void) dealloc
{	
	NSLog(@"DCMView released");
	
	[shortDateString release];
	[localeDictionnary release];
	
	[dcmFilesList release];
	dcmFilesList = 0L;
	
	curDCM = 0L;
	[dcmPixList release];
	dcmPixList = 0L;

	[stringID release];
	
    NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver: self];
	
	[[self openGLContext] makeCurrentContext];
	
    glDeleteLists (fontListGL, 150);
	glDeleteLists(labelFontListGL, 150);
	
	if( pTextureName)
	{
		glDeleteTextures (textureX * textureY, pTextureName);
		free( (Ptr) pTextureName);
		pTextureName = 0L;
	}
	if( blendingTextureName)
	{
		glDeleteTextures ( blendingTextureX * blendingTextureY, blendingTextureName);
		free( (Ptr) blendingTextureName);
		blendingTextureName = 0L;
	}
	if( colorBuf) free( colorBuf);
	if( blendingColorBuf) free( blendingColorBuf);
	
	[curRoiList release];
	curRoiList = 0L;
	
	[dcmRoiList release];
	dcmRoiList = 0L;
	
	[fontColor release];
	[fontGL release];
	[labelFont release];
	[yearOld release];
	
//	[self clearGLContext];
	
	[cursor release];
	[stringTextureCache release];
	
	[_mouseDownTimer invalidate];
	[_mouseDownTimer release];
	
	[destinationImage release];
	
    [super dealloc];
}

- (void) setIndex:(short) index
{
	long	i;
	BOOL	keepIt;
	
	//if( index < 0) index = 0;
	
    if( dcmPixList && index > -1)
    {
		[self stopROIEditing];
		
		if( [[[[dcmFilesList objectAtIndex: 0] valueForKey:@"completePath"] lastPathComponent] isEqualToString:@"Empty.tif"]) noScale = YES;
		else noScale = NO;

		if( [[[self window] windowController] is2DViewer] == YES)
		{
			[[[self window] windowController] setLoadingPause: YES];
		}
		
		[[self window] setAcceptsMouseMovedEvents: YES];
		
        curImage = index;
        if( curImage >= [dcmPixList count]) curImage = [dcmPixList count] -1;
        curDCM = [dcmPixList objectAtIndex:curImage];
		
		[curRoiList release];
		
		if( dcmRoiList) curRoiList = [[dcmRoiList objectAtIndex: curImage] retain];
		else
		{
			curRoiList = [[NSMutableArray alloc] initWithCapacity:0];
		}

		keepIt = NO;
		for( i = 0; i < [curRoiList count]; i++)
		{
			[[curRoiList objectAtIndex:i ] setRoiFont: labelFontListGL :labelFontListGLSize :self];
			
			[[curRoiList objectAtIndex:i ] recompute];
			
			if( curROI == [curRoiList objectAtIndex:i ]) keepIt = YES;
			// Unselect previous ROIs
			//	[[curRoiList objectAtIndex: i] setROIMode : ROI_sleep];
		}
		if( keepIt == NO) curROI = 0L;

        if( curWW != [curDCM ww] | curWL != [curDCM wl] | [curDCM updateToApply] == YES)
		{
			if( [curDCM baseAddr] == 0L)
			{
				[curDCM checkImageAvailble :curWW :curWL];
			}
			else
			{
				[curDCM changeWLWW :curWL: curWW];
			}
		}
        else [curDCM checkImageAvailble :curWW :curWL];
		
//        NSSize  sizeView = [[self enclosingScrollView] contentSize];
//        [self setFrameSize:sizeView];
        [self loadTextures];
		
//		if( [[self window] windowController] != 0L)
//		{
//			if( [[[self window] windowController] is2DViewer] == YES) [[self window] setRepresentedFilename: [curDCM sourceFile]];
//		}


//		if( cross.x != -9999 && cross.y != -9999)
//		{
//			if( [stringID isEqualToString:@"Original"])
//				[[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object:stringID userInfo: 0L];
//		}

		if( [[[self window] windowController] is2DViewer] == YES)
		{
			[[[self window] windowController] setLoadingPause: NO];
		}
    }
    
//    [self display];

	NSEvent *event = [[NSApplication sharedApplication] currentEvent];
	
	[self mouseMoved: event];
	[self setNeedsDisplay:YES];
	
	if (isKeyView) {
		NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:curImage]  forKey:@"curImage"];
		[[NSNotificationCenter defaultCenter]  postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
	}

	[yearOld release];
	yearOld = [[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.yearOld"] retain];
}

-(BOOL) acceptsFirstMouse:(NSEvent*) theEvent
{
	if( currentTool >= 5)   // A ROI TOOL !
	{	 
		return NO;	 
	}	 
	else return YES;
}

- (BOOL)acceptsFirstResponder {
     return YES;
}

- (void) keyDown:(NSEvent *)event
{
	unichar		c = [[event characters] characterAtIndex:0];
	long		xMove = 0, yMove = 0, val;
	BOOL		Jog = NO;


	if( [[self window] windowController]  == browserWindow) { [super keyDown:event]; return;}
	
//	if([stringID isEqualToString:@"Perpendicular"] == YES || [stringID isEqualToString:@"Original"] == YES )
//	{
//		display2DMPRLines =!display2DMPRLines;
//	}
	
	if( [stringID isEqualToString:@"MPR3D"])
	{
		if( c == 127) // Delete
		{
			// NE PAS OUBLIER DE CHANGER EGALEMENT LE CUT !
			long	i;
			BOOL	done = NO;
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selectedModify || [[curRoiList objectAtIndex:i] ROImode] == ROI_drawing)
				{
					if( [[curRoiList objectAtIndex:i] deleteSelectedPoint] == NO)
					{
						[[NSNotificationCenter defaultCenter] postNotificationName: @"removeROI" object:[curRoiList objectAtIndex:i] userInfo: 0L];
						[curRoiList removeObjectAtIndex:i];
						i--;
					}
				}
			}
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)
				{
					[[NSNotificationCenter defaultCenter] postNotificationName: @"removeROI" object:[curRoiList objectAtIndex:i] userInfo: 0L];
					[curRoiList removeObjectAtIndex:i];
					i--;
				}
			}
			
			[[NSNotificationCenter defaultCenter] postNotificationName: @"roiRemovedFromArray" object: 0L userInfo: 0L];
			
			[self setNeedsDisplay:YES];
			
			curROI = 0L;
		}
		else [super keyDown:event];
		return;
	}
	
    if( dcmPixList)
    {
        short   inc, previmage = curImage;
		
		if( flippedData)
		{
			if (c == NSLeftArrowFunctionKey) c = NSRightArrowFunctionKey;
			else if (c == NSRightArrowFunctionKey) c = NSLeftArrowFunctionKey;
			else if( c == NSPageUpFunctionKey) c = NSPageDownFunctionKey;
			else if( c == NSPageDownFunctionKey) c = NSPageUpFunctionKey;
		}
		
		if( c == 127) // Delete
		{
			// NE PAS OUBLIER DE CHANGER EGALEMENT LE CUT !
			long	i;
			BOOL	done = NO;
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selectedModify || [[curRoiList objectAtIndex:i] ROImode] == ROI_drawing)
				{
					if( [[curRoiList objectAtIndex:i] deleteSelectedPoint] == NO)
					{
						[[NSNotificationCenter defaultCenter] postNotificationName: @"removeROI" object:[curRoiList objectAtIndex:i] userInfo: 0L];
						[curRoiList removeObjectAtIndex:i];
						i--;
					}
				}
			}
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)
				{
					[[NSNotificationCenter defaultCenter] postNotificationName: @"removeROI" object:[curRoiList objectAtIndex:i] userInfo: 0L];
					[curRoiList removeObjectAtIndex:i];
					i--;
				}
			}
			
			[[NSNotificationCenter defaultCenter] postNotificationName: @"roiRemovedFromArray" object: 0L userInfo: 0L];
			
			[self setNeedsDisplay: YES];
		}
        else if( c == 13 | c == 3)	// Return - Enter
		{
			if( [[[self window] windowController] is2DViewer] == YES) [[[self window] windowController] PlayStop:[[[self window] windowController] findPlayStopButton]];
		}
		else if( c == 27)			// Escape
		{
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] offFullScreen];
		}
        else if (c == NSLeftArrowFunctionKey)
        {
			if (([event modifierFlags] & NSCommandKeyMask))
			{
				[super keyDown:event];
			}
			else
			{
				if( [event modifierFlags]  & NSControlKeyMask)
				{
					inc = -[curDCM stack];
					curImage += inc;
					if( curImage < 0) curImage = 0;
				}
				else
				{
				
					inc = -_imageRows * _imageColumns;
					curImage -= _imageRows * _imageColumns;
					if( curImage < 0) curImage = 0;
				}
			}
        }
        else if(c ==  NSRightArrowFunctionKey)
        {
			if (([event modifierFlags] & NSCommandKeyMask))
			{
				[super keyDown:event];
			}
			else
			{
				if( [event modifierFlags]  & NSControlKeyMask)
				{
					inc = [curDCM stack];
					curImage += inc;
					if( curImage >= [dcmPixList count]) curImage = [dcmPixList count]-1;
				}
				else
				{
					inc = _imageRows * _imageColumns;
					curImage += _imageRows * _imageColumns;
					if( curImage >= [dcmPixList count]) curImage = [dcmPixList count]-1;
				}
			}
        }
        else if (c == NSUpArrowFunctionKey)
        {
			if( [[[self window] windowController] is2DViewer] == YES && [[[self window] windowController] maxMovieIndex] > 1) [super keyDown:event];
			else
			{
				[self setScaleValue:(scaleValue+1./50.)];
//				scaleValue += 1./50.;
//        
//				if( scaleValue > 100) scaleValue = 100;
            
				[self setNeedsDisplay:YES];
			}
        }
        else if(c ==  NSDownArrowFunctionKey)
        {
            if( [[[self window] windowController] maxMovieIndex] > 1 && [[[self window] windowController] maxMovieIndex] > 1) [super keyDown:event];
			else
			{
				[self setScaleValue:(scaleValue-1./50.)];
//				scaleValue -= 1./50.;
//                    
//				if( scaleValue < 0.01) scaleValue = 0.01;
            
				[self setNeedsDisplay:YES];
			}
        }
		else if (c == NSPageUpFunctionKey)
		{
			inc = -_imageRows * _imageColumns;
			curImage -= _imageRows * _imageColumns;
			if (curImage < 0) curImage = 0;
		}
		else if (c == NSPageDownFunctionKey)
		{
			inc = _imageRows * _imageColumns;
			curImage += _imageRows * _imageColumns;
			if( curImage >= [dcmPixList count]) curImage = [dcmPixList count]-1;
		}
		else if (c == NSHomeFunctionKey)
			curImage = 0;
		else if (c == NSEndFunctionKey)
			curImage = [dcmPixList count]-1; 
		
		
		// SHUTTLE PRO
		else if(c =='z')		// X MOVE LEFT
		{
			Jog = YES;
			xMove = -2;
		}
		else if(c == 'x')		// X MOVE RIGHT
		{
			Jog = YES;
			xMove = 2;
		}
		else if(c =='Z')		// Y MOVE LEFT
		{
			Jog = YES;
			yMove = -2;
		}
		else if(c == 'X')		// Y MOVE RIGHT
		{
			Jog = YES;
			yMove = 2;
		}
        else
        {
            [super keyDown:event];
        }
        
		
		if( Jog == YES)
		{
			if (currentTool == tZoom)
			{
				if( yMove) val = yMove;
				else val = xMove;
				
				[self setScaleValue:(scaleValue+val/10.0)];
//				scaleValue += val/10.0;
//				
//				if( scaleValue < 0.01) scaleValue = 0.01;
//				if( scaleValue > 100) scaleValue = 100;
			}
			
			if (currentTool == tTranslate)
			{
				float xmove, ymove, xx, yy;
			//	GLfloat deg2rad = 3.14159265358979/180.0; 
				
				xmove = xMove*10;
				ymove = yMove*10;
				
				if( xFlipped) xmove = -xmove;
				if( yFlipped) ymove = -ymove;
				
				xx = xmove*cos(rotation*deg2rad) + ymove*sin(rotation*deg2rad);
				yy = xmove*sin(rotation*deg2rad) - ymove*cos(rotation*deg2rad);
				
				origin.x = origin.x + xx;
				origin.y = origin.y + yy;
			}
			
			if (currentTool == tRotate)
			{
				if( yMove) val = yMove * 3;
				else val = xMove * 3;
				
				rotation += val;
				
				
				if( rotation < 0) rotation += 360;
				if( rotation > 360) rotation -= 360;
				

			}
			
			if (currentTool == tNext)
			{
				short   inc, now, prev, previmage;
				
				if( yMove) val = yMove/abs(yMove);
				else val = xMove/abs(xMove);
				
				previmage = curImage;
				
				if( val < 0)
				{
					inc = -1;
					curImage--;
					if( curImage < 0) curImage = [dcmPixList count]-1;
				}
				else if(val> 0)
				{
					inc = 1;
					curImage++;
					if( curImage >= [dcmPixList count]) curImage = 0;
				}
			}
			
			if( currentTool == tWL)
			{
				[curDCM changeWLWW : [curDCM wl] +yMove*10 :[curDCM ww] +xMove*10];
				
				curWW = [curDCM ww];
				curWL = [curDCM wl];
				
				[self loadTextures];
			}
			
			[self setNeedsDisplay:YES];
		}
		
        if( previmage != curImage)
        {
			if( listType == 'i') [self setIndex:curImage];
            else [self setIndexWithReset:curImage :YES];
            
            if( matrix)
            {
                [matrix selectCellAtRow :curImage/[browserWindow COLUMN] column:curImage%[browserWindow COLUMN]];
            }
            
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] adjustSlider];
			
			if( stringID)
			{
				if( [stringID isEqualToString:@"Perpendicular"]  || [stringID isEqualToString:@"Original"] || [stringID isEqualToString:@"MPR3D"] || [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"FinalViewBlending"])
					[[[self window] windowController] adjustSlider];
			}
            // SYNCRO
			[self sendSyncMessage:inc];
			
			[self setNeedsDisplay:YES];
        }
		
		if( [[[self window] windowController] is2DViewer] == YES)
			[[[self window] windowController] propagateSettings];
		
		if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
//		if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];
    }
}


- (void)flagsChanged:(NSEvent *)event
{
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		BOOL update = NO;
		if (([event modifierFlags] & (NSCommandKeyMask | NSShiftKeyMask)) == (NSCommandKeyMask | NSShiftKeyMask))
		{
			if (suppress_labels == NO) update = YES;
			suppress_labels = YES;
		}
		else
		{
			if (suppress_labels == YES) update = YES;
			suppress_labels = NO;
		}		
			
		if (update == YES) [self setNeedsDisplay:YES];
	}
	[super flagsChanged:event];
}

- (void)mouseUp:(NSEvent *)event {
	// get rid of timer
	[self deleteMouseDownTimer];

	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithInt:curImage], @"curImage", event, @"event", nil];

	if( [[self window] isVisible] == NO) return;
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		if( [[[self window] windowController] windowWillClose]) return;
	}
	
	// If caplock is on changes to scale, rotation, zoom, ww/wl will apply only to the current image
	BOOL modifyImageOnly = NO;
	if ([event modifierFlags] & NSAlphaShiftKeyMask) modifyImageOnly = YES;
	
    if( dcmPixList)
    {
		[self mouseMoved: event];	// Update some variables...
		
        if( curImage != startImage && (matrix && browserWindow))
        {
            NSButtonCell *cell = [matrix cellAtRow:curImage/[browserWindow COLUMN] column:curImage%[browserWindow COLUMN]];
            [cell performClick:0L];
            [matrix selectCellAtRow :curImage/[browserWindow COLUMN] column:curImage%[browserWindow COLUMN]];
        }
		
		if ( pluginOverridesMouse && ( [event modifierFlags] & NSControlKeyMask ) ) {  // Simulate Right Mouse Button action
			[nc postNotificationName: @"PLUGINrightMouseUp" object: self userInfo: userInfo];
			[nc postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
			return;
		}
				
		long tool = [self getTool:event];
		
		if( crossMove >= 0) tool = tCross;
		
		if( tool == tCross && ![[self stringID] isEqualToString:@"OrthogonalMPRVIEW"]) {
			[nc postNotificationName: @"crossMove" object: stringID userInfo: [NSDictionary dictionaryWithObject:@"mouseUp" forKey:@"action"]];
		}
		//		else if ( tool == tCross && [[self stringID] isEqualToString:@"OrthogonalMPRVIEW"])
//		{
//			NSPoint     eventLocation = [event locationInWindow];
//			NSRect size = [self frame];
//			eventLocation = [self convertPoint:eventLocation fromView: self];
//			eventLocation = [[[event window] contentView] convertPoint:eventLocation toView:self];
//			eventLocation.y = size.size.height - eventLocation.y;
//			eventLocation = [self ConvertFromView2GL:eventLocation];
//
//			[self setCrossPosition:(long)eventLocation.x : (long)eventLocation.y];
//			[self setNeedsDisplay:YES];
//		}
		
		if( tool == tWL)
		{
			if( [[[self window] windowController] is2DViewer] == YES)
			{
				[[[[self window] windowController] thickSlabController] setLowQuality: NO];
				[curDCM changeWLWW :curWL : curWW];
				[self loadTextures];
				[self setNeedsDisplay:YES];
			}
			
			if( stringID)
			{
				if( [stringID isEqualToString:@"Perpendicular"]  || [stringID isEqualToString:@"Original"] || [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"FinalViewBlending"])
				{
					[[[[self window] windowController] MPR2Dview] adjustWLWW: curWL :curWW :@"set"];
				}
			}
		}
		
		if( [self roiTool: tool])
		{
			long		i;
			NSRect      size = [self frame];
			NSPoint     eventLocation = [event locationInWindow];
			NSPoint		tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
			
			tempPt.y = size.size.height - tempPt.y ;
			
			tempPt = [self ConvertFromView2GL:tempPt];
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				[[curRoiList objectAtIndex:i] mouseRoiUp: tempPt];
				
				if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)	{
					[nc postNotificationName: @"roiSelected" object: [curRoiList objectAtIndex:i] userInfo: nil];
				}
			}
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex: i] valid] == NO)
				{
					[curRoiList removeObjectAtIndex: i];
					i--;
				}
			}
			
			[self setNeedsDisplay:YES];
		}
    }
	
	[nc postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
}

-(float) Magnitude:( NSPoint) Point1 :(NSPoint) Point2 
{
    NSPoint Vector;

    Vector.x = Point2.x - Point1.x;
    Vector.y = Point2.y - Point1.y;

    return (float)sqrt( Vector.x * Vector.x + Vector.y * Vector.y);
}

-(int) DistancePointLine: (NSPoint) Point :(NSPoint) startPoint :(NSPoint) endPoint :(float*) Distance
{
    float   LineMag;
    float   U;
    NSPoint Intersection;
 
    LineMag = [self Magnitude: endPoint : startPoint];
 
    U = ( ( ( Point.x - startPoint.x ) * ( endPoint.x - startPoint.x ) ) +
        ( ( Point.y - startPoint.y ) * ( endPoint.y - startPoint.y ) ) );
		
	U /= ( LineMag * LineMag );

//    if( U < 0.0f || U > 1.0f )
//	{
//		NSLog(@"Distance Err");
//		return 0;   // closest point does not fall within the line segment
//	}
	
    Intersection.x = startPoint.x + U * ( endPoint.x - startPoint.x );
    Intersection.y = startPoint.y + U * ( endPoint.y - startPoint.y );

//    Intersection.Z = LineStart->Z + U * ( endPoint->Z - LineStart->Z );
 
    *Distance = [self Magnitude: Point :Intersection];
 
    return 1;
}

-(void) roiSet:(ROI*) aRoi
{
	[aRoi setRoiFont: labelFontListGL :labelFontListGLSize :self];
}

-(void) roiSet
{
	long i;
	for( i = 0; i < [curRoiList count]; i++)
	{
		[[curRoiList objectAtIndex:i ] setRoiFont: labelFontListGL :labelFontListGLSize :self];
	}
}

-(BOOL) roiTool:(long) tool
{
	switch( tool)
	{
		case tMesure:
		case tROI:
		case tOval:
		case tOPolygon:
		case tCPolygon:
		case tAngle:
		case tArrow:
		case tText:
		case tPencil:
		case tPlain:
		case t2DPoint:
			return YES;
		break;
	}
	
	return NO;
}

- (IBAction) selectAll: (id) sender
{
	long i;
	
	for( i = 0; i < [curRoiList count]; i++)
	{
		[[curRoiList objectAtIndex: i] setROIMode: ROI_selected];
		[[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: [curRoiList objectAtIndex: i] userInfo: nil];
	}
	
	[self setNeedsDisplay:YES];
}

- (IBAction)print:(id)sender
{
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo]; 
	
	NSLog(@"Orientation %d", [printInfo orientation]);
	
	NSImage *im = [self nsimage: [[NSUserDefaults standardUserDefaults] boolForKey: @"ORIGINALSIZE"]];
	
//	NSRect	r = NSMakeRect( 0, 0, [im size].width/2, [im size].height/2);
	
	NSLog( @"w:%f, h:%f", [im size].width, [im size].height);
	
	if ([im size].height < [im size].width)
		[printInfo setOrientation: NSLandscapeOrientation];
	else
		[printInfo setOrientation: NSPortraitOrientation];
	
	//NSRect	r = NSMakeRect( 0, 0, [printInfo paperSize].width, [printInfo paperSize].height);
	
	NSRect	r = NSMakeRect( 0, 0, [im size].width/2, [im size].height/2);
	
	NSImageView *imageView = [[NSImageView alloc] initWithFrame: r];
	
//	r = NSMakeRect( 0, 0, [im size].width, [im size].height);
	
//	NSWindow	*pwindow = [[NSWindow alloc]  initWithContentRect: r styleMask: NSBorderlessWindowMask backing: NSBackingStoreNonretained defer: NO];
	
//	[pwindow setContentView: imageView];
	
	[im setScalesWhenResized:YES];
	
	[imageView setImage: im];
	[imageView setImageScaling: NSScaleProportionally];
	[imageView setImageAlignment: NSImageAlignCenter];
	
	[printInfo setVerticallyCentered:YES];
	[printInfo setHorizontallyCentered:YES];
	
//	[printInfo setTopMargin: 0.0f];
//	[printInfo setBottomMargin: 0.0f];
//	[printInfo setRightMargin: 0.0f];
//	[printInfo setLeftMargin: 0.0f];


	// print imageView
	
    [printInfo setHorizontalPagination:NSFitPagination];
    [printInfo setVerticalPagination:NSFitPagination];
	
	NSPrintOperation * printOperation = [NSPrintOperation printOperationWithView: imageView];
	
	[printOperation runOperation];
	
//	[pwindow release];
	[imageView release];
	[im release];
} 

- (void) checkMouseModifiers:(id) sender
{
	if( [[[NSApplication sharedApplication] currentEvent] modifierFlags])
	{
		long tool = [self getTool: [[NSApplication sharedApplication] currentEvent]];
		[self setCursorForView: tool];
	}
}

-(void) mouseMoved: (NSEvent*) theEvent
{
	if( [[self window] isVisible] == NO) return;
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		if( [[[self window] windowController] windowWillClose]) return;
	}
	
	if( curDCM == 0L) return;
	
	NSPoint     eventLocation = [theEvent locationInWindow];
	NSRect      size = [self frame];
	
	if( dcmPixList == 0L) return;
	
	if( [[self window] isVisible] && [[self window] isKeyWindow])
	{
		BOOL	needUpdate = NO;
		
		float	cpixelMouseValueR = pixelMouseValueR;
		float	cpixelMouseValueG = pixelMouseValueG;
		float	cpixelMouseValueB = pixelMouseValueB;
		float	cmouseXPos = mouseXPos;
		float	cmouseYPos = mouseYPos;
		float	cpixelMouseValue = pixelMouseValue;
		
		eventLocation = [self convertPoint:eventLocation fromView:nil];
		eventLocation.y = size.size.height - eventLocation.y;
		
		NSPoint imageLocation = [self ConvertFromView2GL:eventLocation];
		
		pixelMouseValueR = 0;
		pixelMouseValueG = 0;
		pixelMouseValueB = 0;
		mouseXPos = 0;							// DDP (041214): if outside view bounds show zeros
		mouseYPos = 0;							// otherwise update mouseXPos, mouseYPos, pixelMouseValue
		pixelMouseValue = 0;
		
		if( imageLocation.x >= 0 && imageLocation.x < [curDCM pwidth])	//&& NSPointInRect( eventLocation, size)) <- this doesn't work in MPR Ortho
		{
			if( imageLocation.y >= 0 && imageLocation.y < [curDCM pheight])
			{
				mouseXPos = imageLocation.x;
				mouseYPos = imageLocation.y;
				
				int
					xPos = (int)mouseXPos,
					yPos = (int)mouseYPos;
				
				if( [curDCM isRGB])
				{
					pixelMouseValueR = ((unsigned char*) [curDCM fImage])[ 4 * (xPos + yPos * [curDCM pwidth]) +1];
					pixelMouseValueG = ((unsigned char*) [curDCM fImage])[ 4 * (xPos + yPos * [curDCM pwidth]) +2];
					pixelMouseValueB = ((unsigned char*) [curDCM fImage])[ 4 * (xPos + yPos * [curDCM pwidth]) +3];
				}
				else pixelMouseValue = [curDCM getPixelValueX: xPos Y:yPos];
			}
		}

		if(	cpixelMouseValueR != pixelMouseValueR)	needUpdate = YES;
		if(	cpixelMouseValueG != pixelMouseValueG)	needUpdate = YES;
		if(	cpixelMouseValueB != pixelMouseValueB)	needUpdate = YES;
		if(	cmouseXPos != mouseXPos)	needUpdate = YES;
		if(	cmouseYPos != mouseYPos)	needUpdate = YES;
		if(	cpixelMouseValue != pixelMouseValue)	needUpdate = YES;
		
		float	cblendingMouseXPos = blendingMouseXPos;
		float	cblendingMouseYPos = blendingMouseYPos;
		float	cblendingPixelMouseValue = blendingPixelMouseValue;
		float	cblendingPixelMouseValueR = blendingPixelMouseValueR;
		float	cblendingPixelMouseValueG = blendingPixelMouseValueG;
		float	cblendingPixelMouseValueB = blendingPixelMouseValueB;

		blendingMouseXPos = 0;
		blendingMouseYPos = 0;
		blendingPixelMouseValue = 0;
		blendingPixelMouseValueR = 0;
		blendingPixelMouseValueG = 0;
		blendingPixelMouseValueB = 0;
		
		// Blended view
		if( blendingView)
		{
			NSPoint	offset;
			
			if( [curDCM pixelSpacingX] != 0 && [curDCM pixelSpacingY] != 0 &&  [[NSUserDefaults standardUserDefaults] boolForKey:@"COPYSETTINGS"] == YES)
			{
				float	vectorP[ 9], tempOrigin[ 3], tempOriginBlending[ 3];
				
				// Compute blended view offset
				[curDCM orientation: vectorP];
				
				tempOrigin[ 0] = [curDCM originX] * vectorP[ 0] + [curDCM originY] * vectorP[ 1] + [curDCM originZ] * vectorP[ 2];
				tempOrigin[ 1] = [curDCM originX] * vectorP[ 3] + [curDCM originY] * vectorP[ 4] + [curDCM originZ] * vectorP[ 5];
				tempOrigin[ 2] = [curDCM originX] * vectorP[ 6] + [curDCM originY] * vectorP[ 7] + [curDCM originZ] * vectorP[ 8];
				
				tempOriginBlending[ 0] = [[blendingView curDCM] originX] * vectorP[ 0] + [[blendingView curDCM] originY] * vectorP[ 1] + [[blendingView curDCM] originZ] * vectorP[ 2];
				tempOriginBlending[ 1] = [[blendingView curDCM] originX] * vectorP[ 3] + [[blendingView curDCM] originY] * vectorP[ 4] + [[blendingView curDCM] originZ] * vectorP[ 5];
				tempOriginBlending[ 2] = [[blendingView curDCM] originX] * vectorP[ 6] + [[blendingView curDCM] originY] * vectorP[ 7] + [[blendingView curDCM] originZ] * vectorP[ 8];
				
				offset.x = (tempOrigin[0] + [curDCM pwidth]*[curDCM pixelSpacingX]/2. - (tempOriginBlending[ 0] + [[blendingView curDCM] pwidth]*[[blendingView curDCM] pixelSpacingX]/2.));
				offset.y = (tempOrigin[1] + [curDCM pheight]*[curDCM pixelSpacingY]/2. - (tempOriginBlending[ 1] + [[blendingView curDCM] pheight]*[[blendingView curDCM] pixelSpacingY]/2.));
				
				offset.x /= [[blendingView curDCM] pixelSpacingX];
				offset.y /= [[blendingView curDCM] pixelSpacingY];
			}
			else
			{
				offset.x = 0;
				offset.y = 0;
			}
//			NSLog( @"%f %f", offset.x, offset.y);
			
			// Convert screen position to pixel position in blended image
			float xx, yy;
			NSRect size = [self frame];
			NSPoint a = eventLocation;
						
			if( xFlipped) a.x = size.size.width - a.x;
			if( yFlipped) a.y = size.size.height - a.y;
			
			a.x -= size.size.width/2;
			a.x /= [blendingView scaleValue];
			
			a.y -= size.size.height/2;
			a.y /= [blendingView scaleValue];
			
			xx = a.x*cos([blendingView rotation]*deg2rad) + a.y*sin([blendingView rotation]*deg2rad);
			yy = -a.x*sin([blendingView rotation]*deg2rad) + a.y*cos([blendingView rotation]*deg2rad);

			a.y = yy;
			a.x = xx;
			
			a.x -= ([blendingView origin].x + [blendingView originOffset].x)/[blendingView scaleValue];
			a.y += ([blendingView origin].y + [blendingView originOffset].y)/[blendingView scaleValue];
						
			if( curDCM)
			{
				a.x += [[blendingView curDCM] pwidth]/2.;
				a.y += [[blendingView curDCM] pheight]*[[blendingView curDCM] pixelRatio]/ 2.;
				a.y /= [[blendingView curDCM] pixelRatio];
			}
			
			a.x += offset.x;
			a.y += offset.y;
			
			NSPoint blendedLocation = a;						//= [blendingView ConvertFromView2GL:eventLocation];
			
			if( blendedLocation.x >= 0 && blendedLocation.x < [[blendingView curDCM] pwidth])
			{
				if( blendedLocation.y >= 0 && blendedLocation.y < [[blendingView curDCM] pheight])
				{
					blendingMouseXPos = blendedLocation.x;
					blendingMouseYPos = blendedLocation.y;
					
					int
						xPos = (int)blendingMouseXPos,
						yPos = (int)blendingMouseYPos;
					
					if( [[blendingView curDCM] isRGB])
					{
						blendingPixelMouseValueR = ((unsigned char*) [[blendingView curDCM] fImage])[ 4 * (xPos + yPos * [[blendingView curDCM] pwidth]) +1];
						blendingPixelMouseValueG = ((unsigned char*) [[blendingView curDCM] fImage])[ 4 * (xPos + yPos * [[blendingView curDCM] pwidth]) +2];
						blendingPixelMouseValueB = ((unsigned char*) [[blendingView curDCM] fImage])[ 4 * (xPos + yPos * [[blendingView curDCM] pwidth]) +3];
					}
					else blendingPixelMouseValue = [[blendingView curDCM] getPixelValueX: xPos Y:yPos];
				}
			}
		}
		
		if( cblendingMouseXPos != blendingMouseXPos) needUpdate = YES;
		if( cblendingMouseYPos != blendingMouseYPos) needUpdate = YES;
		if( cblendingPixelMouseValue != blendingPixelMouseValue) needUpdate = YES;
		if( cblendingPixelMouseValueR != blendingPixelMouseValueR) needUpdate = YES;
		if( cblendingPixelMouseValueG != blendingPixelMouseValueG) needUpdate = YES;
		if( cblendingPixelMouseValueB != blendingPixelMouseValueB) needUpdate = YES;
		
		if( needUpdate) [self setNeedsDisplay: YES];
		
		if( stringID)
		{
			if( [stringID isEqualToString:@"Perpendicular"] || [stringID isEqualToString:@"Original"]  || [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"FinalViewBlending"])
			{
				NSView* view = [[[theEvent window] contentView] hitTest:[theEvent locationInWindow]];
				
				if( view == self)
				{
					if( cross.x != -9999 && cross.y != -9999)
					{
						NSPoint tempPt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
						
						tempPt.y = size.size.height - tempPt.y ;
						
						tempPt = [self ConvertFromView2GL:tempPt];
						
						if( tempPt.x > cross.x - BS/scaleValue && tempPt.x < cross.x + BS/scaleValue && tempPt.y > cross.y - BS/scaleValue && tempPt.y < cross.y + BS/scaleValue == YES)	//&& [stringID isEqualToString:@"Original"] 
						{
							if( [theEvent type] == NSLeftMouseDragged || [theEvent type] == NSLeftMouseDown) [[NSCursor closedHandCursor] set];
							else [[NSCursor openHandCursor] set];
						}
						else
						{
							// TESTE SUR LA LIGNE !!!
							float		distance;
							NSPoint		cross1 = cross, cross2 = cross;
							
							cross1.x -=  1000*mprVector[ 0];
							cross1.y -=  1000*mprVector[ 1];

							cross2.x +=  1000*mprVector[ 0];
							cross2.y +=  1000*mprVector[ 1];
							
							[self DistancePointLine:tempPt :cross1 :cross2 :&distance];
							
							if( distance * scaleValue < 10)
							{
								if( [theEvent type] == NSLeftMouseDragged || [theEvent type] == NSLeftMouseDown) [[NSCursor closedHandCursor] set];
								else [[NSCursor openHandCursor] set];
							}
							else [cursor set];
						}
					}
				}
				else [view mouseMoved:theEvent];
			}
		}
	}
	
	if ([[[self window] windowController] is2DViewer] == YES)
	{
		[super mouseMoved: theEvent];
	}
}

static long scrollMode;

- (long) getTool: (NSEvent*) event
{
	long tool;
	
	if( [event type] == NSRightMouseDown || [event type] == NSRightMouseDragged || [event type] == NSRightMouseUp) tool = currentToolRight;
	else if( [event type] == NSOtherMouseDown || [event type] == NSOtherMouseDragged || [event type] == NSOtherMouseUp) tool = tTranslate;
	else tool = currentTool;
	
//	if (([event modifierFlags] & NSControlKeyMask))  tool = tRotate;	<- Pop-up menu
	if (([event modifierFlags] & NSCommandKeyMask))  tool = tTranslate;
	if (([event modifierFlags] & NSAlternateKeyMask))  tool = tWL;
	if (([event modifierFlags] & NSControlKeyMask) && ([event modifierFlags] & NSAlternateKeyMask))  tool = t3Dpoint;
	if( [self roiTool:currentTool] != YES)   // Not a ROI TOOL !
	{
		if (([event modifierFlags] & NSCommandKeyMask) && ([event modifierFlags] & NSAlternateKeyMask))  tool = tRotate;
		if (([event modifierFlags] & NSShiftKeyMask))  tool = tZoom;
	}
	else
	{
		if (([event modifierFlags] & NSCommandKeyMask) && ([event modifierFlags] & NSAlternateKeyMask)) tool = currentTool;
		if (([event modifierFlags] & NSCommandKeyMask)) tool = currentTool;
	}
	
	return tool;
}

- (void) setStartWLWW
{
	startWW = [curDCM ww];
	startWL = [curDCM wl];
	startMin = [curDCM wl] - [curDCM ww]/2;
	startMax = [curDCM wl] + [curDCM ww]/2;
}

- (void)mouseDown:(NSEvent *)event
{
	if( [[self window] isVisible] == NO) return;
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		if( [[[self window] windowController] windowWillClose]) return;
	}
	
	if (_mouseDownTimer) {
		[self deleteMouseDownTimer];
	}
	if ([event type] == NSLeftMouseDown)
		_mouseDownTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self   selector:@selector(startDrag:) userInfo:event  repeats:NO] retain];
	
	
    if( dcmPixList)
    {
		[self erase2DPointMarker];
		if( blendingView) [blendingView erase2DPointMarker];
		
        NSPoint     eventLocation = [event locationInWindow];
        NSRect      size = [self frame];
        long		tool;
		
		[self mouseMoved: event];	// Update some variables...
		
		start = previous = [self convertPoint:eventLocation fromView:self];
        
		tool = [self getTool: event];
		
        startImage = curImage;
        [self setStartWLWW];
        startScaleValue = scaleValue;
        rotationStart = rotation;
		blendingFactorStart = blendingFactor;
		scrollMode = 0;
        		
        originStart = origin;
		originOffsetStart = originOffset;
        
        mesureB = mesureA = [[[event window] contentView] convertPoint:eventLocation toView:self];
        mesureB.y = mesureA.y = size.size.height - mesureA.y ;
        
        roiRect.origin = [[[event window] contentView] convertPoint:eventLocation toView:self];
        roiRect.origin.y = size.size.height - roiRect.origin.y;
        
		if( [[[self window] windowController] is2DViewer] == YES)
		{
			NSPoint tempPt = [self ConvertFromView2GL:mesureA];
			
			NSDictionary	*dict = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithFloat:tempPt.y], @"Y", [NSNumber numberWithLong:tempPt.x],@"X",0L];
			[[NSNotificationCenter defaultCenter] postNotificationName: @"mouseDown" object: [[self window] windowController] userInfo: dict];
		}
		
        if( [event clickCount] > 1 && [self window] == [browserWindow window])
        {
            [browserWindow matrixDoublePressed:nil];
        }
		else if( [event clickCount] > 1 && ([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSCommandKeyMask))
		{
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] setKeyImage: self];
		}
		else if( [event clickCount] > 1 && stringID == 0L)
		{
			float location[ 3];
			
			[curDCM convertPixX: mouseXPos pixY: mouseYPos toDICOMCoords: location];
						
			DCMPix	*thickDCM;
		
			if( [curDCM stack] > 1)
			{
				long maxVal;
				
//				if( flippedData)
//				{
//					maxVal = [dcmPixList count] - ([curDCM ID] + ([curDCM stack]-1));
//					if( maxVal < 0) maxVal = 0;
//					if( maxVal >= [dcmPixList count]) maxVal = [dcmPixList count]-1;
//				}
//				else
				{
					maxVal = curImage+([curDCM stack]-1);
					if( maxVal < 0) maxVal = 0;
					if( maxVal >= [dcmPixList count]) maxVal = [dcmPixList count]-1;
				}
				
				thickDCM = [dcmPixList objectAtIndex: maxVal];
			}
			else thickDCM = 0L;
			
			int pos;
			if( flippedData) pos = [dcmPixList count] -1 -curImage;
			else pos = curImage;
			
			NSDictionary *instructions = [[[NSDictionary alloc] initWithObjectsAndKeys:     self, @"view",
																							[NSNumber numberWithLong: pos],@"Pos",
																							[NSNumber numberWithFloat:[[dcmPixList objectAtIndex:curImage] sliceLocation]],@"Location", 
																							[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"], @"studyID", 
																							curDCM, @"DCMPix",
																							[NSNumber numberWithFloat: syncRelativeDiff],@"offsetsync",
																							[NSNumber numberWithFloat: location[0]],@"point3DX",
																							[NSNumber numberWithFloat: location[1]],@"point3DY",
																							[NSNumber numberWithFloat: location[2]],@"point3DZ",
																							thickDCM, @"DCMPix2",
																							nil]
																							autorelease];
			NSNotificationCenter *nc;
			nc = [NSNotificationCenter defaultCenter];
			[nc postNotificationName: @"sync" object: self userInfo: instructions];
		}
		
		if( cross.x != -9999 && cross.y != -9999)
		{
			NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
			tempPt.y = size.size.height - tempPt.y ;
			
			tempPt = [self ConvertFromView2GL:tempPt];
			if( tempPt.x > cross.x - BS/scaleValue && tempPt.x < cross.x + BS/scaleValue && tempPt.y > cross.y - BS/scaleValue && tempPt.y < cross.y + BS/scaleValue == YES)	//&& [stringID isEqualToString:@"Original"] 
			{
				crossMove = 1;
			}
			else
			{
				// TESTE SUR LA LIGNE !!!
				float		distance;
				NSPoint		cross1 = cross, cross2 = cross;
				
				cross1.x -=  1000*mprVector[ 0];
				cross1.y -=  1000*mprVector[ 1];

				cross2.x +=  1000*mprVector[ 0];
				cross2.y +=  1000*mprVector[ 1];
				
				[self DistancePointLine:tempPt :cross1 :cross2 :&distance];
				
			//	NSLog( @"Dist:%0.0f / %0.0f_%0.0f", distance, tempPt.x, tempPt.y);
				
				if( distance * scaleValue < 10)
				{
					crossMove = 0;
					switchAngle = -1;
				}
				else crossMove = -1;
			}
		}
		else crossMove = -1;
		
		// ROI TOOLS
		if( [self roiTool:tool] == YES && crossMove == -1)
		{
			BOOL	DoNothing = NO;
			long	selected = -1, i, x;
			NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
			tempPt.y = size.size.height - tempPt.y ;
			tempPt = [self ConvertFromView2GL:tempPt];
			
			if ([[NSUserDefaults standardUserDefaults] integerForKey: @"ANNOTATIONS"] == annotNone)
				[[NSUserDefaults standardUserDefaults] setInteger: annotGraphics forKey: @"ANNOTATIONS"];
			
			BOOL roiFound = NO;
			
			if (!(([event modifierFlags] & NSCommandKeyMask) && ([event modifierFlags] & NSShiftKeyMask)))
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex: i] clickInROI: tempPt :[curDCM pwidth]/2. :[curDCM pheight]/2. :scaleValue :YES])
				{
					selected = i;
					roiFound = YES;
				}
			}
			
			if( roiFound == NO)
			{
				for( i = 0; i < [curRoiList count]; i++)
				{
					if( [[curRoiList objectAtIndex: i] clickInROI: tempPt :[curDCM pwidth]/2. :[curDCM pheight]/2. :scaleValue :NO])
					{
						selected = i;
					}
				}
			}
			
			if (([event modifierFlags] & NSShiftKeyMask) && !([event modifierFlags] & NSCommandKeyMask))
			{
				if( selected != -1)
				{
					if( [[curRoiList objectAtIndex: selected] ROImode] == ROI_selected) 
					{
						[[curRoiList objectAtIndex: selected] setROIMode: ROI_sleep];
						DoNothing = YES;
					}
				}
			}
			else
			{
				if( selected == -1 || ( [[curRoiList objectAtIndex: selected] ROImode] != ROI_selected &&  [[curRoiList objectAtIndex: selected] ROImode] != ROI_selectedModify))
				{
					// Unselect previous ROIs
					for( i = 0; i < [curRoiList count]; i++) [[curRoiList objectAtIndex: i] setROIMode : ROI_sleep];
				}
			}
			
			if( DoNothing == NO)
			{
				if( selected >= 0 && drawingROI == NO)
				{
					curROI = 0L;
					
					long roiVal = [[curRoiList objectAtIndex: selected] clickInROI: tempPt :[curDCM pwidth]/2. :[curDCM pheight]/2. :scaleValue :YES];
					if( roiVal == ROI_sleep) roiVal = [[curRoiList objectAtIndex: selected] clickInROI: tempPt :[curDCM pwidth]/2. :[curDCM pheight]/2. :scaleValue :NO];
					
					[[curRoiList objectAtIndex: selected] setROIMode: roiVal];
					
					NSArray *winList = [[NSApplication sharedApplication] windows];
					BOOL	found = NO;
					
					for( i = 0; i < [winList count]; i++)
					{
						if( [[[[winList objectAtIndex:i] windowController] windowNibName] isEqualToString:@"ROI"])
						{
							found = YES;
							[[[winList objectAtIndex:i] windowController] setROI: [curRoiList objectAtIndex: selected] :[[self window] windowController]];
						}
					}
					
					if( [event clickCount] > 1 && [[[self window] windowController] is2DViewer] == YES)
					{
						if( found == NO)
						{
							ROIWindow* roiWin = [[ROIWindow alloc] initWithROI: [curRoiList objectAtIndex: selected] :[[self window] windowController]];
							[roiWin showWindow:self];
						}
					}
				}
				else // Start drawing a new ROI !
				{
					if( curROI)
					{
						drawingROI = [curROI mouseRoiDown: tempPt : scaleValue];
						
						if( drawingROI == NO)
						{
							curROI = 0L;
						}
						
						if( [curROI ROImode] == ROI_selected)
							[[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: curROI userInfo: nil];
					}
					else
					{
						// Unselect previous ROIs
						for( i = 0; i < [curRoiList count]; i++) [[curRoiList objectAtIndex: i] setROIMode : ROI_sleep];
						
						ROI*		aNewROI;
						NSString	*roiName = 0L, *finalName;
						long		counter;
						BOOL		existsAlready;
						
						drawingROI = NO;
						
						curROI = aNewROI = [[ROI alloc] initWithType: currentTool :[curDCM pixelSpacingX] :[curDCM pixelSpacingY] :NSMakePoint( [curDCM originX], [curDCM originY])];
											
						if ( [ROI defaultName] != nil ) {
							[aNewROI setName: [ROI defaultName]];
						}
						else { 
							switch( currentTool)
							{
								case  tOval:
									roiName = [NSString stringWithString:@"Oval "];
									break;
									
								case tOPolygon:
								case tCPolygon:
									roiName = [NSString stringWithString:@"Polygon "];
									break;
									
								case tAngle:
									roiName = [NSString stringWithString:@"Angle "];
									break;
									
								case tArrow:
									roiName = [NSString stringWithString:@"Arrow "];
									break;
								
								case tPlain:
								case tPencil:
									roiName = [NSString stringWithString:@"ROI "];
									break;
									
								case tMesure:
									roiName = [NSString stringWithString:@"Measurement "];
									break;
									
								case tROI:
									roiName = [NSString stringWithString:@"Rectangle "];
									break;
									
								case t2DPoint:
									roiName = [NSString stringWithString:@"Point "];
									break;
							}
							
							if( roiName)
							{
								counter = 1;
								
								do
								{
									existsAlready = NO;
									
									finalName = [roiName stringByAppendingFormat:@"%d", counter++];
									
									for( i = 0; i < [dcmRoiList count]; i++)
									{
										for( x = 0; x < [[dcmRoiList objectAtIndex: i] count]; x++)
										{
											if( [[[[dcmRoiList objectAtIndex: i] objectAtIndex: x] name] isEqualToString: finalName])
											{
												existsAlready = YES;
											}
										}
									}
									
								} while (existsAlready != NO);
								
								[aNewROI setName: finalName];
							}
						}
						
						// Create aliases of current ROI to the entire series
						if (([event modifierFlags] & NSShiftKeyMask) && !([event modifierFlags] & NSCommandKeyMask))
						{
							for( i = 0; i < [dcmRoiList count]; i++)
							{
								[[dcmRoiList objectAtIndex: i] addObject: aNewROI];
							}
						}
						else [curRoiList addObject: aNewROI];
						
						[aNewROI setRoiFont: labelFontListGL :labelFontListGLSize :self];
						drawingROI = [aNewROI mouseRoiDown: tempPt :scaleValue];
						if( drawingROI == NO)
						{
							curROI = 0L;
						}
						
						if( [aNewROI ROImode] == ROI_selected)
							[[NSNotificationCenter defaultCenter] postNotificationName: @"roiSelected" object: aNewROI userInfo: nil];
						
						NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:	aNewROI,							@"ROI",
																								[NSNumber numberWithInt:curImage],	@"sliceNumber", 
																								nil];
					   
						[[NSNotificationCenter defaultCenter] postNotificationName: @"addROI" object:self userInfo:userInfo];
						
						[aNewROI release];
					}
				}
			}
			
			for( x = 0; x < [dcmRoiList count]; x++)
			{
				for( i = 0; i < [[dcmRoiList objectAtIndex: x] count]; i++)
				{
					if( [[[dcmRoiList objectAtIndex: x] objectAtIndex: i] valid] == NO)
					{
						[[dcmRoiList objectAtIndex: x] removeObjectAtIndex: i];
						i--;
					}
				}
			}
		}
		
		[self mouseDragged:event];
    }
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	float				reverseScrollWheel;					// DDP (050913): allow reversed scroll wheel preference.
	
	if( [[self window] isVisible] == NO) return;
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		if( [[[self window] windowController] windowWillClose]) return;
	}
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey: @"Scroll Wheel Reversed"])
		reverseScrollWheel=-1.0;
	else
		reverseScrollWheel=1.0;
	
	if( flippedData) reverseScrollWheel *= -1.0;
	
    if( dcmPixList)
    {
        short inc;
        
		if( [stringID isEqualToString:@"OrthogonalMPRVIEW"])
		{
			//[[[self window] windowController] saveCrossPositions];
			[[self controller] saveCrossPositions];
			float change;
			if( fabs( [theEvent deltaY]) >  fabs( [theEvent deltaX]))
			{
				change = reverseScrollWheel * [theEvent deltaY];
				if( change > 0)
				{
					change = ceil( change);
					if( change < 1) change = 1;
				}
				else
				{
					change = floor( change);
					if( change > -1) change = -1;		
				}
				if ( [self isKindOfClass: [OrthogonalMPRView class]] ) {
					[(OrthogonalMPRView*)self scrollTool: 0 : (long)change];
				}
			}
			else
			{
				change = reverseScrollWheel * [theEvent deltaX];
				if( change > 0)
				{
					change = ceil( change);
					if( change < 1) change = 1;
				}
				else
				{
					change = floor( change);
					if( change > -1) change = -1;		
				}
				if ( [self isKindOfClass: [OrthogonalMPRView class]] ) {
					[(OrthogonalMPRView*)self scrollTool: 0 : (long)change];
				}
			}
			
			[self mouseMoved: [[NSApplication sharedApplication] currentEvent]];
		}
		else if( [stringID isEqualToString:@"MPR3D"])
		{
			[super scrollWheel: theEvent];
		}
		else if( [stringID isEqualToString:@"previewDatabase"])
		{
			[super scrollWheel: theEvent];
		}
		else if( [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"Perpendicular"] )
		{
			[super scrollWheel: theEvent];
		}
		else
		{
			if( fabs( [theEvent deltaY]) * 2.0f >  fabs( [theEvent deltaX]))
			{
				if( [theEvent modifierFlags]  & NSShiftKeyMask)
				{
					float change = reverseScrollWheel * [theEvent deltaY] / 2.5f;
					
					if( change > 0)
					{
						change = ceil( change);
						if( change < 1) change = 1;
						
						inc = [curDCM stack] * change;
						curImage += inc;
					}
					else
					{
						change = floor( change);
						if( change > -1) change = -1;
						
						inc = [curDCM stack] * change;
						curImage += inc;
					}
				}
				else
				{
					float change = reverseScrollWheel * [theEvent deltaY] / 2.5f;
					
					if( change > 0)
					{
						change = ceil( change);
						if( change < 1) change = 1;
						
						inc = _imageRows * _imageColumns * change;
						curImage += inc;
					}
					else
					{
						change = floor( change);
						if( change > -1) change = -1;
						
						inc = _imageRows * _imageColumns * change;
						curImage += inc;
					}
				}
			}
			else if( fabs( [theEvent deltaX]) > 0.7)
			{
				[self mouseMoved: theEvent];	// Update some variables...
				
//				NSLog(@"delta x: %f", [theEvent deltaX]);
				
				float sScaleValue = scaleValue;
				
				[self setScaleValue:sScaleValue + [theEvent deltaX] * scaleValue / 10];
//				scaleValue = sScaleValue + [theEvent deltaX] * scaleValue / 10;
//				if( scaleValue < 0.01) scaleValue = 0.01;
//				if( scaleValue > 100) scaleValue = 100;
				
				origin.x = ((origin.x * scaleValue) / sScaleValue);
				origin.y = ((origin.y * scaleValue) / sScaleValue);
				
				originOffset.x = ((originOffset.x * scaleValue) / sScaleValue);
				originOffset.y = ((originOffset.y * scaleValue) / sScaleValue);
				
				if( [[[self window] windowController] is2DViewer] == YES)
					[[[self window] windowController] propagateSettings];
				
				if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
		//		if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];
				
				[self setNeedsDisplay:YES];
			}
			
			if( curImage < 0) curImage = [dcmPixList count]-1;
			if( curImage >= [dcmPixList count]) curImage = 0;
					
			if( listType == 'i') [self setIndex:curImage];
			else [self setIndexWithReset:curImage :YES];
			
			if( matrix)
			{
				[matrix selectCellAtRow :curImage/[browserWindow COLUMN] column:curImage%[browserWindow COLUMN]];
			}
			
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] adjustSlider];    //mouseDown:theEvent];
				
			if( stringID)
			{
				if( [stringID isEqualToString:@"Perpendicular"] || [stringID isEqualToString:@"Original"] || [stringID isEqualToString:@"MPR3D"] || [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"FinalViewBlending"])
					[[[self window] windowController] adjustSlider];
			}
			
			// SYNCRO
			[self sendSyncMessage:inc];
			
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] propagateSettings];
			
			if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
//			if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];
			
			[self setNeedsDisplay:YES];
		}
    }
	
	NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:curImage]  forKey:@"curImage"];
	[nc postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
}

- (void) otherMouseDown:(NSEvent *)event
{
	[self mouseDown: event];
}

- (void) rightMouseDown:(NSEvent *)event {
	
	if ( pluginOverridesMouse ) {
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:curImage], @"curImage", event, @"event", nil];
		[nc postNotificationName: @"PLUGINrightMouseDown" object: self userInfo: userInfo];
		return;
	}
		
	[self mouseDown: event];
	
//    if( dcmPixList)
//    {
//        NSPoint eventLocation = [event locationInWindow];
//        start = [self convertPoint:eventLocation fromView:self];
//        
//        startScaleValue = scaleValue;
//		originStart = origin;
//		originOffsetStart = originOffset;
//		originOffsetRegistrationStart = originOffsetRegistration;
//    }
}

//added by lpysher 4/22/04. Mimics single click to open contextual menu.
- (void) rightMouseUp:(NSEvent *)event {
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					   [NSNumber numberWithInt:curImage], @"curImage", event, @"event", nil];

	if ( pluginOverridesMouse ) {
		[nc postNotificationName: @"PLUGINrightMouseUp" object: self userInfo: userInfo];
	}
	else {
		 if ([event clickCount] == 1)
				[NSMenu popUpContextMenu:[self menu] withEvent:event forView:self];
		//[super rightMouseUp:event];
	}
	
	[nc postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
}

- (void)otherMouseDragged:(NSEvent *)event
{
	[self mouseDragged:(NSEvent *)event];
}

- (void)rightMouseDragged:(NSEvent *)event {
	
	if ( pluginOverridesMouse ) {
		[self mouseMoved: event];	// Update some variables...
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:curImage], @"curImage", event, @"event", nil];
		[nc postNotificationName: @"PLUGINrightMouseDragged" object: self userInfo: userInfo];
		return;
	}
	
	[self mouseDragged:(NSEvent *)event];
}

-(NSMenu*) menuForEvent:(NSEvent *)theEvent {
	if ( pluginOverridesMouse ) return nil;  // Turn off contextual menu.  RBR 3/26/06
	return [self menu];  // Default
}
	
-(NSString*) stringID
{
	return stringID;
}

-(void) setStringID:(NSString*) str
{
	if( str != stringID)
	{
		[stringID release];
		stringID = str;
		[stringID retain];
	}
}

- (void)mouseDragged:(NSEvent *)event
{

	if( [[self window] isVisible] == NO) return;
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		if( [[[self window] windowController] windowWillClose]) return;
	}
	
	if (_dragInProgress == NO && ([event deltaX] != 0 || [event deltaY] != 0)) {
		[self deleteMouseDownTimer];
	}
	
	if (_dragInProgress == YES) return;
	
    if( dcmPixList)
    {
        NSPoint     eventLocation = [event locationInWindow];
        NSPoint     current = [self convertPoint:eventLocation fromView:self];
        short       tool;
        NSRect      size = [self frame];
		
		[self mouseMoved: event];	// Update some variables...
		
		tool = [self getTool: event];
		
		if( crossMove >= 0) tool = tCross;
		
		if( [self roiTool: tool])
		{
			long	i;
			BOOL	action = NO;
			
			NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
			
			tempPt.y = size.size.height - tempPt.y;
			tempPt = [self ConvertFromView2GL:tempPt];
			
			for( i = 0; i < [curRoiList count]; i++)
			{
				if( [[curRoiList objectAtIndex:i] mouseRoiDragged: tempPt :[event modifierFlags] :scaleValue] != NO)
				{
					action = YES;
				}
			}
			
			if( action == NO) // Is there a selected ROI -> rotate or move it
			{
				if (([event modifierFlags] & NSCommandKeyMask) && ([event modifierFlags] & NSAlternateKeyMask))
				{
					NSPoint rotatePoint = [[[event window] contentView] convertPoint:start toView:self];
					rotatePoint.y = size.size.height - start.y ;
					rotatePoint = [self ConvertFromView2GL: rotatePoint];
			
					NSPoint offset;
					float   xx, yy;
					
					offset.x = - (previous.x - current.x) / scaleValue;
					offset.y =  (previous.y - current.y) / scaleValue;
					
					for( i = 0; i < [curRoiList count]; i++)
					{
						if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected) [[curRoiList objectAtIndex:i] rotate: offset.x :rotatePoint];
					}
				}
				else if (([event modifierFlags] & NSCommandKeyMask) && !([event modifierFlags] & NSShiftKeyMask))
				{
					NSPoint rotatePoint = [[[event window] contentView] convertPoint:start toView:self];
					rotatePoint.y = size.size.height - start.y ;
					rotatePoint = [self ConvertFromView2GL: rotatePoint];
			
					NSPoint offset;
					float   xx, yy;
					
					offset.x = - (previous.x - current.x) / scaleValue;
					offset.y =  (previous.y - start.y) / scaleValue;
					
					for( i = 0; i < [curRoiList count]; i++)
					{
						if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected) [[curRoiList objectAtIndex:i] resize: 1 + (offset.x)/20. :rotatePoint];
					}
				}
				else
				{
					NSPoint offset;
					float   xx, yy;
					
					offset.x = - (previous.x - current.x) / scaleValue;
					offset.y =  (previous.y - current.y) / scaleValue;
					
					if( xFlipped) offset.x = -offset.x;
					if( yFlipped) offset.y = -offset.y;
					
					xx = offset.x;		yy = offset.y;
					
					offset.x = xx*cos(rotation*deg2rad) + yy*sin(rotation*deg2rad);
					offset.y = -xx*sin(rotation*deg2rad) + yy*cos(rotation*deg2rad);
					
					offset.y /=  [curDCM pixelRatio];
					
					for( i = 0; i < [curRoiList count]; i++)
					{
						if( [[curRoiList objectAtIndex:i] ROImode] == ROI_selected)
						{
							[[curRoiList objectAtIndex:i] roiMove: offset];
						}
					}
				}
			}
		}
		
		if( tool == t3DRotate)
		{
			if( [stringID isEqualToString:@"MPR3D"] == YES)
			{
				NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
				tempPt.y = size.size.height - tempPt.y ;
				
				tempPt = [self ConvertFromView2GL:tempPt];
				
				[[NSNotificationCenter defaultCenter] postNotificationName: @"planesMove" object:stringID userInfo: [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithFloat:tempPt.y], @"Y", [NSNumber numberWithLong:tempPt.x],@"X",0L]];
			}
		}
		
		if( tool == tCross && ![[self stringID] isEqualToString:@"OrthogonalMPRVIEW"])
		{
			crossPrev = cross;
			
			if( crossMove)
			{
				NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
				tempPt.y = size.size.height - tempPt.y ;
				
				
				cross = [self ConvertFromView2GL:tempPt];
			}
			else
			{
				float newAngle;
				
				NSPoint tempPt = [[[event window] contentView] convertPoint:eventLocation toView:self];
				tempPt.y = size.size.height - tempPt.y ;
				
				tempPt = [self ConvertFromView2GL:tempPt];
				
				tempPt.x -= cross.x;
				tempPt.y -= cross.y;
				
				if( tempPt.y < 0) newAngle = 180 + atan( (float) tempPt.x / (float) tempPt.y) / deg2rad;
				else newAngle = atan( (float) tempPt.x / (float) tempPt.y) / deg2rad;
				newAngle += 90;
				newAngle = 360 - newAngle;
				
			//	NSLog(@"%2.2f", newAngle);
				if( switchAngle == -1)
				{
					if( fabs( newAngle - angle) > 90 && fabs( newAngle - angle) < 270)
					{
						switchAngle = 1;
					}
					else switchAngle = 0;
				}
				
			//	NSLog(@"AV: old angle: %2.2f new angle: %2.2f", angle, newAngle);
				
				if( switchAngle == 1)
				{
			//		NSLog(@"switch");
					newAngle -= 180;
					if( newAngle < 0) newAngle += 360;
				}
				
			//	NSLog(@"AP: old angle: %2.2f new angle: %2.2f", angle, newAngle);
				
				[self setMPRAngle: newAngle];
			}
			
			[self mouseMoved: event];	// Update some variables...
			
			[[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object:stringID userInfo: [NSDictionary dictionaryWithObject:@"dragged" forKey:@"action"]];
		}
		else if ( tool == tCross && [[self stringID] isEqualToString:@"OrthogonalMPRVIEW"] && ( [event type] != NSRightMouseDown))
		{
			eventLocation = [self convertPoint:eventLocation fromView: self];
			eventLocation = [[[event window] contentView] convertPoint:eventLocation toView:self];
			eventLocation.y = size.size.height - eventLocation.y;
			eventLocation = [self ConvertFromView2GL:eventLocation];
			
			if ( [self isKindOfClass: [OrthogonalMPRView class]] ) {
				[(OrthogonalMPRView*)self setCrossPosition:(long)eventLocation.x : (long)eventLocation.y];
			}
			
			//[self setCrossPosition:(long)mouseXPos : (long)mouseYPos];
			[self setNeedsDisplay:YES];
		}
		
//        if (tool == tMesure)
//        {
//            mesureB = [[[event window] contentView] convertPoint:eventLocation toView:self];
//            mesureB.y = size.size.height - mesureB.y ;
//        }
        
//        if( tool == tROI)
//        {
//            roiRect.size.width = (current.x - start.x);
//            roiRect.size.height = -(current.y - start.y);
//			
//			[self setQuartzExtreme: YES];
//        }
//		else [self setQuartzExtreme: NO];

        if (tool == tZoom)
        {
			[self setScaleValue: (startScaleValue + (current.y - start.y) / (80.))];
			
//          scaleValue = startScaleValue + (current.y - start.y)/50.;
//          
//          if( scaleValue < 0.01) scaleValue = 0.01;
//          if( scaleValue > 100) scaleValue = 100;

			origin.x = ((originStart.x * scaleValue) / startScaleValue);
			origin.y = ((originStart.y * scaleValue) / startScaleValue);
			
			originOffset.x = ((originOffsetStart.x * scaleValue) / startScaleValue);
			originOffset.y = ((originOffsetStart.y * scaleValue) / startScaleValue);
			
			//set value for Series Object Presentation State
			if ([[[self window] windowController] is2DViewer] == YES)
			{
				[[self seriesObj] setValue:[NSNumber numberWithFloat:scaleValue] forKey:@"scale"];
				[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.x] forKey:@"xOffset"];
				[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.y] forKey:@"yOffset"];
				[[self seriesObj] setValue:[NSNumber numberWithFloat:1] forKey:@"displayStyle"];
			}
		}
        
        if (tool == tTranslate)
        {
            float xmove, ymove, xx, yy;
       //     GLfloat deg2rad = 3.14159265358979/180.0; 
            
            xmove = (current.x - start.x);
            ymove = -(current.y - start.y);
            
            if( xFlipped) xmove = -xmove;
            if( yFlipped) ymove = -ymove;
            
            xx = xmove*cos((rotation)*deg2rad) + ymove*sin((rotation)*deg2rad);
            yy = xmove*sin((rotation)*deg2rad) - ymove*cos((rotation)*deg2rad);
            
            origin.x = originStart.x + xx;
            origin.y = originStart.y + yy;
			
			//set value for Series Object Presentation State
			if ([[[self window] windowController] is2DViewer] == YES)
			{
				[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.x] forKey:@"xOffset"];
				[[self seriesObj] setValue:[NSNumber numberWithFloat:origin.y] forKey:@"yOffset"];
			}
        }
        
        if (tool == tRotate)
        {
            rotation = rotationStart - (current.x - start.x);
			while( rotation < 0) rotation += 360;
			while( rotation > 360) rotation -= 360;
			
			//set value for Series Object Presentation State
			[[self seriesObj] setValue:[NSNumber numberWithFloat:rotation] forKey:@"rotationAngle"];
			//NSLog(@"set Series rotation: %f", [[[self seriesObj] valueForKey:@"rotationAngle"] floatValue]);
        }
        
        if (tool == tNext)
        {
            short   inc, now, prev, previmage;
			BOOL	movie4Dmove = NO;
            
			if( scrollMode == 0)
			{
				if( fabs( start.x - current.x) < fabs( start.y - current.y))
				{
					prev = start.y/2;
					now = current.y/2;
					if( fabs( start.y - current.y) > 3) scrollMode = 1;
				}
				else if( fabs( start.x - current.x) >= fabs( start.y - current.y))
				{
					prev = start.x/2;
					now = current.x/2;
					if( fabs( start.x - current.x) > 3) scrollMode = 2;
				}
				
			//	NSLog(@"scrollMode : %d", scrollMode);
			}
			
			if( movie4Dmove == NO && ![stringID isEqualToString:@"OrthogonalMPRVIEW"])
			{
				previmage = curImage;
				
				if( scrollMode == 2)
				{
					curImage = startImage + ((current.x - start.x) * [dcmPixList count] )/ ([self frame].size.width/2);
				}
				else if( scrollMode == 1)
				{
					curImage = startImage + ((start.y - current.y) * [dcmPixList count] )/ ([self frame].size.height/2);
				}
				
				if( curImage < 0) curImage = 0;
				if( curImage >= [dcmPixList count]) curImage = [dcmPixList count] -1;
				
//				if( prev > now)
//				{
//					inc = -1;
//					if( curImage > 0) curImage--;
//				}
//				else if(prev < now)
//				{
//					inc = 1;
//					if( curImage < [dcmPixList count]-1) curImage++;
//				}
				
				if(previmage != curImage)
				{
					if( listType == 'i') [self setIndex:curImage];
					else [self setIndexWithReset:curImage :YES];
					
					if( matrix) [matrix selectCellAtRow :curImage/[browserWindow COLUMN] column:curImage%[browserWindow COLUMN]];
					
					if( [[[self window] windowController] is2DViewer] == YES)
						[[[self window] windowController] adjustSlider];
					
					if( stringID) [[[self window] windowController] adjustSlider];
					
					// SYNCRO
					[self sendSyncMessage: curImage - previmage];
				}
			}
			else if( movie4Dmove == NO && [stringID isEqualToString:@"OrthogonalMPRVIEW"])
			{
				long from, to, startLocation;
				if( scrollMode == 2)
				{
					from = current.x;
					to = start.x;
				}
				else if( scrollMode == 1)
				{
					from = start.y;
					to = current.y;
				}
				else
				{
					from = 0;
					to = 0;
				}
				
				if ( fabs( from-to ) >= 1 && [self isKindOfClass: [OrthogonalMPRView class]] ) {
					[(OrthogonalMPRView*)self scrollTool: from : to];
				}
			}

        }        
		
        if( tool == tWL && !([stringID isEqualToString:@"OrthogonalMPRVIEW"] && (blendingView != 0L)))
        {
		//	ICI
			float WWAdapter = startWW / 200.0;
			
			if( WWAdapter < 0.001) WWAdapter = 0.001;
			
			if( [[[self window] windowController] is2DViewer] == YES)
			{
				[[[[self window] windowController] thickSlabController] setLowQuality: YES];
			}
			
			if( [stringID isEqualToString:@"MPR3D"] == NO)
			{
				if( [[[dcmFilesList objectAtIndex:0] valueForKey:@"modality"] isEqualToString:@"PT"])
				{
					float startlevel;
					float endlevel;
					
					switch( [[NSUserDefaults standardUserDefaults] integerForKey: @"PETWindowingMode"])
					{
						case 0:
							[curDCM changeWLWW : startWL + (current.y -  start.y)*WWAdapter :startWW + (current.x -  start.x)*WWAdapter];
						break;
						
						case 1:
							endlevel = startMax + (current.y -  start.y) * WWAdapter ;
							
							[curDCM changeWLWW: (endlevel - startMin) / 2 + [[NSUserDefaults standardUserDefaults] integerForKey: @"PETMinimumValue"]: endlevel - startMin];
						break;
						
						case 2:
							endlevel = startMax + (current.y -  start.y) * WWAdapter ;
							startlevel = startMin + (current.x -  start.x) * WWAdapter ;
							
							if( startlevel < 0) startlevel = 0;
							
							[curDCM changeWLWW: startlevel + (endlevel - startlevel) / 2: endlevel - startlevel];
						break;
					}
				}
				else
				{
					[curDCM changeWLWW : startWL + (current.y -  start.y)*WWAdapter :startWW + (current.x -  start.x)*WWAdapter];
				}
			}
			
            curWW = [curDCM ww];
            curWL = [curDCM wl];
            
			if( [[[self window] windowController] is2DViewer] == YES)
			{
				[[[self window] windowController] setCurWLWWMenu: NSLocalizedString(@"Other", 0L)];
			}
			[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateWLWWMenu" object:NSLocalizedString(@"Other", 0L) userInfo: 0L];
			
			if( stringID)
			{
				if( [stringID isEqualToString:@"MPR3D"])
				{
					[[NSNotificationCenter defaultCenter] postNotificationName: @"SetWLWWMPR3D" object:self userInfo: [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithLong:(current.y -  previous.y)], @"WL", [NSNumber numberWithLong:(current.x -  previous.x)],@"WW",0L]];
				}
				else if( [stringID isEqualToString:@"Perpendicular"] || [stringID isEqualToString:@"FinalView"] || [stringID isEqualToString:@"Original"] || [stringID isEqualToString:@"FinalViewBlending"])
				{
					[[[[self window] windowController] MPR2Dview] adjustWLWW: curWL :curWW :@"dragged"];
				}
				else if( [stringID isEqualToString:@"OrthogonalMPRVIEW"])
				{
					// change Window level
					//[[[self window] windowController] setWLWW: curWL :curWW];
					[self setWLWW: curWL :curWW];
				}
				else [self loadTextures];
			}
			else [self loadTextures];
			
			[[NSNotificationCenter defaultCenter] postNotificationName: @"changeWLWW" object: curDCM userInfo:0L];
			
			if( [curDCM SUVConverted] == NO)
			{
				//set value for Series Object Presentation State
				[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW] forKey:@"windowWidth"];
				[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL] forKey:@"windowLevel"];
			}
			else
			{
				if( [[[self window] windowController] is2DViewer] == YES)
				{
					[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW / [[[self window] windowController] factorPET2SUV]] forKey:@"windowWidth"];
					[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL / [[[self window] windowController] factorPET2SUV]] forKey:@"windowLevel"];
				}
			}
		}
        else if( tool == tWL && [stringID isEqualToString:@"OrthogonalMPRVIEW"] && (blendingView != 0L))
		{
			// change blending value
			blendingFactor = blendingFactorStart + (current.x - start.x);
				
			if( blendingFactor < -256.0) blendingFactor = -256.0;
			if( blendingFactor > 256.0) blendingFactor = 256.0;
			
			[self setBlendingFactor: blendingFactor];
		}
        previous = current;
        
    //    [self checkVisible];
        [self setNeedsDisplay:YES];
		
		if( [[[self window] windowController] is2DViewer] == YES)
			[[[self window] windowController] propagateSettings];
		
		if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
//		if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];
    }
}

- (void) getWLWW:(float*) wl :(float*) ww
{
	if( curDCM == 0L) NSLog(@"curDCM 0L");
	else
	{
		if(wl) *wl = [curDCM wl];
		if(ww) *ww = [curDCM ww];
	}
}

- (void) changeWLWW: (NSNotification*) note
{
	DCMPix	*otherPix = [note object];
	
	if( [dcmPixList containsObject: otherPix])
	{
		float iwl, iww;
		
		iww = [otherPix ww];
		iwl = [otherPix wl];
		
		if( iww != [curDCM ww] || iwl != [curDCM wl])
			[self setWLWW: iwl :iww];
	}
	
	if( blendingView)
	{
		if( [[blendingView dcmPixList] containsObject: otherPix])
		{
			float iwl, iww;
			
			iww = [otherPix ww];
			iwl = [otherPix wl];
			
			if( iww != [[blendingView curDCM] ww] || iwl != [[blendingView curDCM] wl])
			{
				[blendingView setWLWW: iwl :iww];
				[self loadTextures];
				[self setNeedsDisplay:YES];
			}
		}
	}
}

- (void) setWLWW:(float) wl :(float) ww
{
    [curDCM changeWLWW :wl : ww];
    
    curWW = [curDCM ww];
    curWL = [curDCM wl];
    
	[[NSNotificationCenter defaultCenter] postNotificationName: @"changeWLWW" object: curDCM userInfo:0L];
	
    [self loadTextures];
    [self setNeedsDisplay:YES];
	
	//set value for Series Object Presentation State
	if( [curDCM SUVConverted] == NO)
	{
		[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW] forKey:@"windowWidth"];
		[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL] forKey:@"windowLevel"];
	}
	else
	{
		if( [[[self window] windowController] is2DViewer] == YES)
		{
			[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW / [[[self window] windowController] factorPET2SUV]] forKey:@"windowWidth"];
			[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL / [[[self window] windowController] factorPET2SUV]] forKey:@"windowLevel"];
		}
	}
}

- (void)discretelySetWLWW:(float)wl :(float)ww;
{
    [curDCM changeWLWW :wl : ww];
    
    curWW = [curDCM ww];
    curWL = [curDCM wl];
	
    [self loadTextures];
    [self setNeedsDisplay:YES];
	
	//set value for Series Object Presentation State
	if( [curDCM SUVConverted] == NO)
	{
		[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW] forKey:@"windowWidth"];
		[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL] forKey:@"windowLevel"];
	}
	else
	{
		if( [[[self window] windowController] is2DViewer] == YES)
		{
			[[self seriesObj] setValue:[NSNumber numberWithFloat:curWW / [[[self window] windowController] factorPET2SUV]] forKey:@"windowWidth"];
			[[self seriesObj] setValue:[NSNumber numberWithFloat:curWL / [[[self window] windowController] factorPET2SUV]] forKey:@"windowLevel"];
		}
	}
}

-(void) setFusion:(short) mode :(short) stacks
{
	long i, x;
	
	thickSlabMode = mode;
	thickSlabStacks = stacks;
	
	for ( i = 0; i < [dcmPixList count]; i ++)
	{
		[[dcmPixList objectAtIndex:i] setFusion:mode :stacks :flippedData];
	}
	
	[self setIndex: curImage];
}

-(void) multiply:(DCMView*) bV
{
	[curDCM imageArithmeticMultiplication: [bV curDCM]];
	
	[curDCM changeWLWW :curWL: curWW];
	[self loadTextures];
	[self setNeedsDisplay: YES];
}

-(void) subtract:(DCMView*) bV
{
	[curDCM imageArithmeticSubtraction: [bV curDCM]];
	
	[curDCM changeWLWW :curWL: curWW];
	[self loadTextures];
	[self setNeedsDisplay: YES];
}

-(void) setBlending:(DCMView*) bV
{
	float orientA[9], orientB[9];
	float result[3];
	
	if( blendingView == bV) return;
	
	if( bV)
	{
		if( [bV curDCM])
		{
			[curDCM orientation:orientA];
			[[bV curDCM] orientation:orientB];
			
			if( orientB[ 6] == 0 && orientB[ 7] == 0 && orientB[ 8] == 0) { blendingView = bV;	return;}
			if( orientA[ 6] == 0 && orientA[ 7] == 0 && orientA[ 8] == 0) { blendingView = bV;	return;}
			
			// normal vector of planes
			
			result[0] = fabs( orientB[ 6] - orientA[ 6]);
			result[1] = fabs( orientB[ 7] - orientA[ 7]);
			result[2] = fabs( orientB[ 8] - orientA[ 8]);
			
			if( result[0] + result[1] + result[2] > 0.01)  // Planes are not paralel!
			{
				if( NSRunCriticalAlertPanel(NSLocalizedString(@"2D Planes",nil),NSLocalizedString(@"These 2D planes are not parallel. The result in 2D will be distorted.",nil), NSLocalizedString(@"Continue",nil), NSLocalizedString(@"Cancel",nil),nil) != NSAlertDefaultReturn)
				{
					blendingView = 0L;
				}
				else blendingView = bV;
			}
			else blendingView = bV;
		}
	}
	else blendingView = 0L;
}

-(void) getCLUT:( unsigned char**) r : (unsigned char**) g : (unsigned char**) b
{
	*r = redTable;
	*g = greenTable;
	*b = blueTable;
}

- (void) setCLUT:( unsigned char*) r : (unsigned char*) g : (unsigned char*) b
{
	long i;

	if( r)
	{
		for( i = 0; i < 256; i++)
		{
			redTable[i] = r[i];
			greenTable[i] = g[i];
			blueTable[i] = b[i];
		}
		
		colorTransfer = YES;
	}
	else
	{
		colorTransfer = NO;
		if( colorBuf) free(colorBuf);
		colorBuf = 0L;
		
		for( i = 0; i < 256; i++)
		{
			redTable[i] = i;
			greenTable[i] = i;
			blueTable[i] = i;
		}
	}
	
//JF not necesary	[curDCM changeWLWW :curWL: curWW];
}

- (void) setConv:(short*) m :(short) s :(short) norm
{
	long i;
	
	kernelsize = s;
	normalization = norm;
	if( m)
	{
		long i;
		for( i = 0; i < kernelsize*kernelsize; i++)
		{
			kernel[i] = m[i];
		}
	}
	
	for ( i = 0; i < [dcmPixList count]; i ++)
	{
		[[dcmPixList objectAtIndex:i] setConvolutionKernel:m :kernelsize :norm];
	}
}

-(short) curImage
{
    return curImage;
}

- (BOOL) suppressLabels
{
	return suppress_labels;
}


- (void) prepareOpenGL
{

}

- (float) syncRelativeDiff {return syncRelativeDiff;}
- (void) setSyncRelativeDiff: (float) v
{
	syncRelativeDiff = v;
	NSLog(@"sync relative: %2.2f", syncRelativeDiff);
}

+ (void) computePETBlendingCLUT
{
	if( PETredTable != 0L) free( PETredTable);
	if( PETgreenTable != 0L) free( PETgreenTable);
	if( PETblueTable != 0L) free( PETblueTable);
	
	NSDictionary		*aCLUT = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: @"CLUT"] objectForKey: [[NSUserDefaults standardUserDefaults] stringForKey:@"PET Blending CLUT"]];
	if( aCLUT)
	{
		long				i;
		NSArray				*array;
		
		PETredTable = malloc( 256);
		PETgreenTable = malloc( 256);
		PETblueTable = malloc( 256);
		
		array = [aCLUT objectForKey:@"Red"];
		for( i = 0; i < 256; i++)
		{
			PETredTable[i] = [[array objectAtIndex: i] longValue];
		}
		
		array = [aCLUT objectForKey:@"Green"];
		for( i = 0; i < 256; i++)
		{
			PETgreenTable[i] = [[array objectAtIndex: i] longValue];
		}
		
		array = [aCLUT objectForKey:@"Blue"];
		for( i = 0; i < 256; i++)
		{
			PETblueTable[i] = [[array objectAtIndex: i] longValue];
		}
	}
}

- (void) initFont
{
	fontListGL = glGenLists (150);
	fontGL = [[NSFont fontWithName: [[NSUserDefaults standardUserDefaults] stringForKey:@"FONTNAME"] size: [[NSUserDefaults standardUserDefaults] floatForKey: @"FONTSIZE"]] retain];
	if( fontGL == 0L) fontGL = [[NSFont fontWithName:@"Geneva" size:14] retain];
	[fontGL makeGLDisplayListFirst:' ' count:150 base: fontListGL :fontListGLSize :NO];
	stringSize = [self sizeOfString:@"B" forFont:fontGL];
}

- (id)initWithFrameInt:(NSRect)frameRect
{
	long i;
	
	if( PETredTable == 0L)
	{
		[DCMView computePETBlendingCLUT];
	}
	
	yearOld = 0L;
	shortDateString = [[[NSUserDefaults standardUserDefaults] stringForKey: NSShortDateFormatString] retain];
	localeDictionnary = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] retain];
	syncSeriesIndex = -1;
	mouseXPos = mouseYPos = 0;
	pixelMouseValue = 0;
	originOffset.x = originOffset.y = 0;
	curDCM = 0L;
	curRoiList = 0L;
	blendingMode = 0;
	display2DPoint = NSMakePoint(0,0);
	colorBuf = 0L;
	blendingColorBuf = 0L;
	stringID = 0L;
	mprVector[ 0] = 0;
	mprVector[ 1] = 0;
	crossMove = -1;
	previousViewSize.height = previousViewSize.width = 0;
	slab = 0;
	cursor = 0L;
	cursorSet = NO;
	syncRelativeDiff = 0;
	volumicSeries = YES;
	currentToolRight = [[NSUserDefaults standardUserDefaults] integerForKey: @"DEFAULTRIGHTTOOL"];
	thickSlabMode = 0;
	thickSlabStacks = 0;
	
	suppress_labels = NO;
	
    NSLog(@"DCMView alloc");

    // Init pixel format attribs
    NSOpenGLPixelFormatAttribute attrs[] =
    {
			NSOpenGLPFAAccelerated,
			NSOpenGLPFANoRecovery,
            NSOpenGLPFADoubleBuffer,
//			NSOpenGLPFAOffScreen,
			NSOpenGLPFADepthSize, (NSOpenGLPixelFormatAttribute)32,
			0
	};
	// Get pixel format from OpenGL
    NSOpenGLPixelFormat* pixFmt = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs] autorelease];
    if (!pixFmt)
    {
    //        NSRunCriticalAlertPanel(NSLocalizedString(@"OPENGL ERROR",nil), NSLocalizedString(@"Not able to run Quartz Extreme: OpenGL+Quartz. Update your video hardware!",nil), NSLocalizedString(@"OK",nil), nil, nil);
	//		exit(1);
    }
	self = [super initWithFrame:frameRect pixelFormat:pixFmt];
	
	blendingView = 0L;
	pTextureName = 0L;
	blendingTextureName = 0L;
	
    NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
    [nc addObserver: self
           selector: @selector(doSyncronize:)
               name: @"sync"
             object: nil];
	
	[nc	addObserver: self
			selector: @selector(Display3DPoint:)
				name: @"Display3DPoint"
			object: nil];
	
	[nc addObserver: self
           selector: @selector(roiChange:)
               name: @"roiChange"
             object: nil];
			 
	[nc addObserver: self
           selector: @selector(roiSelected:)
               name: @"roiSelected"
             object: nil];
             
    [nc addObserver: self
           selector: @selector(updateView:)
               name: @"updateView"
             object: nil];
	
	[nc addObserver: self
           selector: @selector(setFontColor:)
               name:  @"DCMNewFontColor" 
             object: nil];
			 
	[nc addObserver: self
           selector: @selector(changeGLFontNotification:)
               name:  @"changeGLFontNotification" 
             object: nil];
			
	[nc	addObserver: self
			selector: @selector(changeWLWW:)
				name: @"changeWLWW"
			object: nil];
	
    colorTransfer = NO;
	
	for (i = 0; i < 256; i++)
	{
		alphaTable[i] = 0xFF;
		redTable[i] = i;
		greenTable[i] = i;
		blueTable[i] = i;
	}

	redFactor = 1.0;
	greenFactor = 1.0;
	blueFactor = 1.0;
	
    dcmPixList = 0L;
    dcmFilesList = 0L;
    
    [[self openGLContext] makeCurrentContext];
    

    blendingFactor = 0.5;
	
    long swap = 1;  // LIMIT SPEED TO VBL if swap == 1
	[[self openGLContext] setValues:&swap forParameter:NSOpenGLCPSwapInterval];
    
	[self FindMinimumOpenGLCapabilities];
    
//	glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);

    // This hint is for antialiasing
	glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);

    // Setup some basic OpenGL stuff
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	fontColor = nil;
	
	[self initFont];
		
	labelFontListGL = glGenLists (150);
	labelFont = [[NSFont fontWithName:@"Monaco" size:12] retain];
	[labelFont makeGLDisplayListFirst:' ' count:150 base: labelFontListGL :labelFontListGLSize :YES];
	
    currentTool = tWL;
    
	cross.x = cross.y = -9999;
	
	mouseModifiers = [[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(checkMouseModifiers:) userInfo:nil repeats:YES] retain];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name: NSWindowWillCloseNotification object: 0L];
	
    return self;
}

- (void)windowWillClose:(NSNotification *)notification
{
	if( [notification object] == [self window])
	{
	//	NSLog( @"windowWillClose - NSView level");
		[mouseModifiers invalidate];
		[mouseModifiers release];
		mouseModifiers = 0L;
		
		[[NSNotificationCenter defaultCenter] removeObserver: self];
	}
}

-(BOOL) volumicSeries
{
	return volumicSeries;
}

-(void) sendSyncMessage:(short) inc
{
	if( numberOf2DViewer > 1   && isKeyView)	//&&  [[self window] isMainWindow] == YES
    {
		DCMPix	*thickDCM;
		
		if( [curDCM stack] > 1)
		{
			long maxVal;
			
			if( flippedData) maxVal = curImage-([curDCM stack]-2);
			else maxVal = curImage+[curDCM stack]-1;
			if( maxVal < 0) maxVal = 0;
			if( maxVal >= [dcmPixList count]) maxVal = [dcmPixList count]-1;
			
			thickDCM = [dcmPixList objectAtIndex: maxVal];
		}
		else thickDCM = 0L;
		
		int pos;
		if( flippedData) pos = [dcmPixList count] -1 -curImage;
		else pos = curImage;
		
		if( flippedData) inc = -inc;
		
        NSDictionary *instructions = [[[NSDictionary alloc] initWithObjectsAndKeys:     self, @"view",
																						[NSNumber numberWithLong:pos],@"Pos",
                                                                                        [NSNumber numberWithLong:inc], @"Direction",
																						[NSNumber numberWithFloat:[[dcmPixList objectAtIndex:curImage] sliceLocation]],@"Location", 
																						[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"], @"studyID", 
																						[NSNumber numberWithFloat: syncRelativeDiff],@"offsetsync",
																						curDCM, @"DCMPix",
																						thickDCM, @"DCMPix2",		// WARNING thickDCM can be nil!! nothing after this one...
																						 nil]
                                                                                        autorelease];
        
		if( stringID == 0L)		//|| [stringID isEqualToString:@"Original"])
		{
			NSNotificationCenter *nc;
			nc = [NSNotificationCenter defaultCenter];
			[nc postNotificationName: @"sync" object: self userInfo: instructions];
		}
		
		if( blendingView) // We have to reload the blending image..
		{
			[self loadTextures];
			[self setNeedsDisplay: YES];
		}
    }
	/*
	else
		NSLog(@"NO message. Not key");
	*/
}

-(void) becomeMainWindow
{
	[self setFusion: thickSlabMode :-1];

	NSLog(@"BecomeMainWindow");
	[[NSNotificationCenter defaultCenter] postNotificationName: @"DCMNewImageViewResponder" object: self userInfo: 0L];
	
	sliceVector[ 0] = sliceVector[ 1] = sliceVector[ 2] = 0;
	sliceVector2[ 0] = sliceVector2[ 1] = sliceVector2[ 2] = 0;
	[self sendSyncMessage:0];
	
	[appController setXFlipped: xFlipped];
	[appController setYFlipped: yFlipped];
	
	[self setNeedsDisplay:YES];
}

-(void) becomeKeyWindow
{

	sliceVector[ 0] = sliceVector[ 1] = sliceVector[ 2] = 0;
	sliceVector2[ 0] = sliceVector2[ 1] = sliceVector2[ 2] = 0;
	[self sendSyncMessage:0];
	[self setNeedsDisplay:YES];
}

-(void) computeSlice:(DCMPix*) oPix :(DCMPix*) oPix2
// COMPUTE SLICE PLANE
{
	float vectorA[ 9], vectorA2[ 9], vectorB[ 9];
	float originA[ 3], originA2[ 3], originB[ 3];
	
	originA[ 0] = [oPix originX];		originA[ 1] = [oPix originY];		originA[ 2] = [oPix originZ];
	if( oPix2)
	{
		originA2[ 0] = [oPix2 originX];		originA2[ 1] = [oPix2 originY];		originA2[ 2] = [oPix2 originZ];
	}
	originB[ 0] = [curDCM originX];		originB[ 1] = [curDCM originY];		originB[ 2] = [curDCM originZ];
	
	[oPix orientation: vectorA];		//vectorA[0] = vectorA[6];	vectorA[1] = vectorA[7];	vectorA[2] = vectorA[8];
	if( oPix2) [oPix orientation: vectorA2];
	[curDCM orientation: vectorB];		//vectorB[0] = vectorB[6];	vectorB[1] = vectorB[7];	vectorB[2] = vectorB[8];
	
	if( intersect3D_2Planes( vectorA+6, originA, vectorB+6, originB, sliceVector, slicePoint) == noErr)
	{
		float perpendicular[ 3], temp[ 3];
		
		CROSS( perpendicular, sliceVector, (vectorB + 6));
		
		// Now reoriente this 3D line in our plane!
		
	//	NSLog(@"slice compute");
		
		temp[ 0] = sliceVector[ 0] * vectorB[ 0] + sliceVector[ 1] * vectorB[ 1] + sliceVector[ 2] * vectorB[ 2];
		temp[ 1] = sliceVector[ 0] * vectorB[ 3] + sliceVector[ 1] * vectorB[ 4] + sliceVector[ 2] * vectorB[ 5];
		temp[ 2] = sliceVector[ 0] * vectorB[ 6] + sliceVector[ 1] * vectorB[ 7] + sliceVector[ 2] * vectorB[ 8];
		sliceVector[ 0] = temp[ 0];
		sliceVector[ 1] = temp[ 1];
		sliceVector[ 2] = temp[ 2];
		
		slicePoint[ 0] -= [curDCM originX];
		slicePoint[ 1] -= [curDCM originY];
		slicePoint[ 2] -= [curDCM originZ];
		
	//	slicePoint[ 0] += perpendicular[ 0] * [oPix sliceThickness]/2.;
	//	slicePoint[ 1] += perpendicular[ 1] * [oPix sliceThickness]/2.;
	//	slicePoint[ 2] += perpendicular[ 2] * [oPix sliceThickness]/2.;
		
		slicePointO[ 0] = slicePoint[ 0] + perpendicular[ 0] * [oPix sliceThickness]/2.;
		slicePointO[ 1] = slicePoint[ 1] + perpendicular[ 1] * [oPix sliceThickness]/2.;
		slicePointO[ 2] = slicePoint[ 2] + perpendicular[ 2] * [oPix sliceThickness]/2.;
		
		slicePointI[ 0] = slicePoint[ 0] - perpendicular[ 0] * [oPix sliceThickness]/2.;
		slicePointI[ 1] = slicePoint[ 1] - perpendicular[ 1] * [oPix sliceThickness]/2.;
		slicePointI[ 2] = slicePoint[ 2] - perpendicular[ 2] * [oPix sliceThickness]/2.;
		
		temp[ 0] = slicePoint[ 0] * vectorB[ 0] + slicePoint[ 1] * vectorB[ 1] + slicePoint[ 2]*vectorB[ 2];
		temp[ 1] = slicePoint[ 0] * vectorB[ 3] + slicePoint[ 1] * vectorB[ 4] + slicePoint[ 2]*vectorB[ 5];
		temp[ 2] = slicePoint[ 0] * vectorB[ 6] + slicePoint[ 1] * vectorB[ 7] + slicePoint[ 2]*vectorB[ 8];
		slicePoint[ 0] = temp[ 0];	slicePoint[ 1] = temp[ 1];	slicePoint[ 2] = temp[ 2];
	
		slicePoint[ 0] /= [curDCM pixelSpacingX];
		slicePoint[ 1] /= [curDCM pixelSpacingY];
		slicePoint[ 0] -= [curDCM pwidth]/2.;
		slicePoint[ 1] -= [curDCM pheight]/2.;
		
		temp[ 0] = slicePointO[ 0] * vectorB[ 0] + slicePointO[ 1] * vectorB[ 1] + slicePointO[ 2]*vectorB[ 2];
		temp[ 1] = slicePointO[ 0] * vectorB[ 3] + slicePointO[ 1] * vectorB[ 4] + slicePointO[ 2]*vectorB[ 5];
		temp[ 2] = slicePointO[ 0] * vectorB[ 6] + slicePointO[ 1] * vectorB[ 7] + slicePointO[ 2]*vectorB[ 8];
		slicePointO[ 0] = temp[ 0];	slicePointO[ 1] = temp[ 1];	slicePointO[ 2] = temp[ 2];
		slicePointO[ 0] /= [curDCM pixelSpacingX];
		slicePointO[ 1] /= [curDCM pixelSpacingY];
		slicePointO[ 0] -= [curDCM pwidth]/2.;
		slicePointO[ 1] -= [curDCM pheight]/2.;
		
		temp[ 0] = slicePointI[ 0] * vectorB[ 0] + slicePointI[ 1] * vectorB[ 1] + slicePointI[ 2]*vectorB[ 2];
		temp[ 1] = slicePointI[ 0] * vectorB[ 3] + slicePointI[ 1] * vectorB[ 4] + slicePointI[ 2]*vectorB[ 5];
		temp[ 2] = slicePointI[ 0] * vectorB[ 6] + slicePointI[ 1] * vectorB[ 7] + slicePointI[ 2]*vectorB[ 8];
		slicePointI[ 0] = temp[ 0];	slicePointI[ 1] = temp[ 1];	slicePointI[ 2] = temp[ 2];
		slicePointI[ 0] /= [curDCM pixelSpacingX];
		slicePointI[ 1] /= [curDCM pixelSpacingY];
		slicePointI[ 0] -= [curDCM pwidth]/2.;
		slicePointI[ 1] -= [curDCM pheight]/2.;
	}
	else
	{
		sliceVector[0] = sliceVector[1] = sliceVector[2] = 0; 
		slicePoint[0] = slicePoint[1] = slicePoint[2] = 0; 
	}
	
	if( oPix2)
	{
		if( intersect3D_2Planes( vectorA2+6, originA2, vectorB+6, originB, sliceVector2, slicePoint2) == noErr)
		{
			float perpendicular[ 3], temp[ 3];
			
			CROSS( perpendicular, sliceVector2, (vectorB + 6));
			
			// Now reoriente this 3D line in our plane!
			
			temp[ 0] = sliceVector2[ 0] * vectorB[ 0] + sliceVector2[ 1] * vectorB[ 1] + sliceVector2[ 2] * vectorB[ 2];
			temp[ 1] = sliceVector2[ 0] * vectorB[ 3] + sliceVector2[ 1] * vectorB[ 4] + sliceVector2[ 2] * vectorB[ 5];
			temp[ 2] = sliceVector2[ 0] * vectorB[ 6] + sliceVector2[ 1] * vectorB[ 7] + sliceVector2[ 2] * vectorB[ 8];
			sliceVector2[ 0] = temp[ 0];
			sliceVector2[ 1] = temp[ 1];
			sliceVector2[ 2] = temp[ 2];
			
			slicePoint2[ 0] -= [curDCM originX];
			slicePoint2[ 1] -= [curDCM originY];
			slicePoint2[ 2] -= [curDCM originZ];
			
			slicePoint2[ 0] += perpendicular[ 0] * [oPix2 sliceThickness]/2.;
			slicePoint2[ 1] += perpendicular[ 1] * [oPix2 sliceThickness]/2.;
			slicePoint2[ 2] += perpendicular[ 2] * [oPix2 sliceThickness]/2.;
			
			slicePointO2[ 0] = slicePoint2[ 0] + perpendicular[ 0] * [oPix2 sliceThickness]/2.;
			slicePointO2[ 1] = slicePoint2[ 1] + perpendicular[ 1] * [oPix2 sliceThickness]/2.;
			slicePointO2[ 2] = slicePoint2[ 2] + perpendicular[ 2] * [oPix2 sliceThickness]/2.;
			
			slicePointI2[ 0] = slicePoint2[ 0] - perpendicular[ 0] * [oPix2 sliceThickness]/2.;
			slicePointI2[ 1] = slicePoint2[ 1] - perpendicular[ 1] * [oPix2 sliceThickness]/2.;
			slicePointI2[ 2] = slicePoint2[ 2] - perpendicular[ 2] * [oPix2 sliceThickness]/2.;
			
			temp[ 0] = slicePoint2[ 0] * vectorB[ 0] + slicePoint2[ 1] * vectorB[ 1] + slicePoint2[ 2]*vectorB[ 2];
			temp[ 1] = slicePoint2[ 0] * vectorB[ 3] + slicePoint2[ 1] * vectorB[ 4] + slicePoint2[ 2]*vectorB[ 5];
			temp[ 2] = slicePoint2[ 0] * vectorB[ 6] + slicePoint2[ 1] * vectorB[ 7] + slicePoint2[ 2]*vectorB[ 8];
			slicePoint2[ 0] = temp[ 0];	slicePoint2[ 1] = temp[ 1];	slicePoint2[ 2] = temp[ 2];
		
			slicePoint2[ 0] /= [curDCM pixelSpacingX];
			slicePoint2[ 1] /= [curDCM pixelSpacingY];
			slicePoint2[ 0] -= [curDCM pwidth]/2.;
			slicePoint2[ 1] -= [curDCM pheight]/2.;
			
			temp[ 0] = slicePointO2[ 0] * vectorB[ 0] + slicePointO2[ 1] * vectorB[ 1] + slicePointO2[ 2]*vectorB[ 2];
			temp[ 1] = slicePointO2[ 0] * vectorB[ 3] + slicePointO2[ 1] * vectorB[ 4] + slicePointO2[ 2]*vectorB[ 5];
			temp[ 2] = slicePointO2[ 0] * vectorB[ 6] + slicePointO2[ 1] * vectorB[ 7] + slicePointO2[ 2]*vectorB[ 8];
			slicePointO2[ 0] = temp[ 0];	slicePointO2[ 1] = temp[ 1];	slicePointO2[ 2] = temp[ 2];
			slicePointO2[ 0] /= [curDCM pixelSpacingX];
			slicePointO2[ 1] /= [curDCM pixelSpacingY];
			slicePointO2[ 0] -= [curDCM pwidth]/2.;
			slicePointO2[ 1] -= [curDCM pheight]/2.;
			
			temp[ 0] = slicePointI2[ 0] * vectorB[ 0] + slicePointI2[ 1] * vectorB[ 1] + slicePointI2[ 2]*vectorB[ 2];
			temp[ 1] = slicePointI2[ 0] * vectorB[ 3] + slicePointI2[ 1] * vectorB[ 4] + slicePointI2[ 2]*vectorB[ 5];
			temp[ 2] = slicePointI2[ 0] * vectorB[ 6] + slicePointI2[ 1] * vectorB[ 7] + slicePointI2[ 2]*vectorB[ 8];
			slicePointI2[ 0] = temp[ 0];	slicePointI2[ 1] = temp[ 1];	slicePointI2[ 2] = temp[ 2];
			slicePointI2[ 0] /= [curDCM pixelSpacingX];
			slicePointI2[ 1] /= [curDCM pixelSpacingY];
			slicePointI2[ 0] -= [curDCM pwidth]/2.;
			slicePointI2[ 1] -= [curDCM pheight]/2.;
		}
		else
		{
			sliceVector2[0] = sliceVector2[1] = sliceVector2[2] = 0; 
			slicePoint2[0] = slicePoint2[1] = slicePoint2[2] = 0; 
		}
	}
	else
	{
		sliceVector2[0] = sliceVector2[1] = sliceVector2[2] = 0; 
		slicePoint2[0] = slicePoint2[1] = slicePoint2[2] = 0; 
	}
}

-(void) doSyncronize:(NSNotification*)note
{
	if (![[[note object] superview] isEqual:[self superview]])
	{
	BOOL	stringOK = NO;
	
	long prevImage = curImage;
	
//	if( stringID)
//	{
//		if( [stringID isEqualToString:@"Original"]) stringOK = YES;
//	}
//	
//	if( [[note object] stringID])
//	{
//		if( [[[note object] stringID] isEqualToString:@"Original"]) stringOK = YES;
//	}
//	
//	if( stringID == 0L && [[note object] stringID] == 0L) stringOK = YES;
	
	if( [[self window] isVisible] == NO)
	{
		NSLog(@"not visible...");
		return;
	}
	
    if( [note object] != self && isKeyView == YES && matrix == 0 && stringID == 0L && [[note object] stringID] == 0L && curImage > -1 )   //|| [[[note object] stringID] isEqualToString:@"Original"] == YES))   // Dont change the browser preview....
    {
        NSDictionary *instructions = [note userInfo];

        long		diff = [[instructions valueForKey: @"Direction"] longValue];
        long		pos = [[instructions valueForKey: @"Pos"] longValue];
		float		loc = [[instructions valueForKey: @"Location"] floatValue];
		float		offsetsync = [[instructions valueForKey: @"offsetsync"] floatValue];
		NSString	*oStudyId = [instructions valueForKey: @"studyID"];
		DCMPix		*oPix = [instructions valueForKey: @"DCMPix"];
		DCMPix		*oPix2 = [instructions valueForKey: @"DCMPix2"];
		DCMView		*otherView = [instructions valueForKey: @"view"];
		long		stack = [oPix stack];
		float		destPoint3D[ 3];
		BOOL		point3D = NO;
		
		if( [instructions valueForKey: @"offsetsync"] == 0L) { NSLog(@"err offsetsync");	return;}
		
		if( [instructions valueForKey: @"view"] == 0L) { NSLog(@"err view");	return;}
		
		if( [instructions valueForKey: @"point3DX"])
		{
			destPoint3D[ 0] = [[instructions valueForKey: @"point3DX"] floatValue];
			destPoint3D[ 1] = [[instructions valueForKey: @"point3DY"] floatValue];
			destPoint3D[ 2] = [[instructions valueForKey: @"point3DZ"] floatValue];
			
			point3D = YES;
		}
		
		if( [oStudyId isEqualToString:[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"]] || ALWAYSSYNC == YES || syncSeriesIndex != -1)  // We received a message from the keyWindow -> display the slice cut to our window!
		{
			if( [oStudyId isEqualToString:[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"]])
			{
				if( [oStudyId isEqualToString:[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"]])
				{
					[self computeSlice: oPix :oPix2];
				}
				else
				{
					sliceVector2[0] = sliceVector2[1] = sliceVector2[2] = 0; 
					slicePoint2[0] = slicePoint2[1] = slicePoint2[2] = 0; 
				}
				
				// Double-Click -> find the nearest point on our plane, go to this plane and draw the intersection!
				if( point3D)
				{
					float	resultPoint[ 3];
					
					long newIndex = [self findPlaneAndPoint: destPoint3D :resultPoint];
					
					if( newIndex != -1)
					{
						curImage = newIndex;
						
						slicePoint3D[ 0] = resultPoint[ 0];
						slicePoint3D[ 1] = resultPoint[ 1];
						slicePoint3D[ 2] = resultPoint[ 2];
					}
					else
					{
						slicePoint3D[ 0] = 0;
						slicePoint3D[ 1] = 0;
						slicePoint3D[ 2] = 0;
					}
				}
				else
				{
					slicePoint3D[ 0] = 0;
					slicePoint3D[ 1] = 0;
					slicePoint3D[ 2] = 0;
				}
			}
			
			// Absolute Vodka
			if( syncro == syncroABS && point3D == NO && syncSeriesIndex == -1)
			{
				if( flippedData) curImage = [dcmPixList count] -1 -pos;
				else curImage = pos;
				
				//NSLog(@"Abs");
				
				if( curImage >= [dcmPixList count]) curImage = [dcmPixList count] - 1;
				if( curImage < 0) curImage = 0;
			}
			
			// Based on Location
			if( (syncro == syncroLOC && point3D == NO) || syncSeriesIndex != -1)
			{
				if( volumicSeries == YES && [otherView volumicSeries] == YES)
				{
					if( (sliceVector[0] == 0 && sliceVector[1] == 0 && sliceVector[2] == 0) || syncSeriesIndex != -1)  // Planes are parallel !
					{
						BOOL	noSlicePosition, everythingLoaded = YES;
						float   firstSliceLocation;
						long	index, i;
						float   smallestdiff = -1, fdiff, slicePosition;
						
						if( [[[self window] windowController] is2DViewer] == YES)
							everythingLoaded = [[[self window] windowController] isEverythingLoaded];
						
						noSlicePosition = NO;
						
						if( everythingLoaded) firstSliceLocation = [[dcmPixList objectAtIndex: 0] sliceLocation];
						else firstSliceLocation = [[[dcmFilesList objectAtIndex: 0] valueForKey:@"sliceLocation"] floatValue];
						
						for( i = 0; i < [dcmFilesList count]; i++)
						{
							if( everythingLoaded) slicePosition = [[dcmPixList objectAtIndex: i] sliceLocation];
							else slicePosition = [[[dcmFilesList objectAtIndex: i] valueForKey:@"sliceLocation"] floatValue];
							
							fdiff = slicePosition - loc;
							
							if( [oStudyId isEqualToString:[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"]] == NO || syncSeriesIndex != -1)
							{						
								if( [otherView syncSeriesIndex] != -1)
								{
									slicePosition -= [[dcmPixList objectAtIndex: syncSeriesIndex] sliceLocation];
									
									fdiff = slicePosition - (loc - [[[otherView dcmPixList] objectAtIndex: [otherView syncSeriesIndex]] sliceLocation]);
								}
								else if( ALWAYSSYNC == NO) noSlicePosition = YES;
							}
							
							if( fdiff < 0) fdiff = -fdiff;
							
							if( fdiff < smallestdiff || smallestdiff == -1)
							{
								smallestdiff = fdiff;
								index = i;
							}
						}
						
						if( noSlicePosition == NO)
						{
							curImage = index;
							
							//NSLog(@"Loc");
							
							if( curImage >= [dcmFilesList count]) curImage = [dcmFilesList count]-1;
							if( curImage < 0) curImage = 0;
						}
					}
				}
				else if( volumicSeries == NO && [otherView volumicSeries] == NO)	// For example time or functional series
				{
					if( flippedData) curImage = [dcmPixList count] -1 -pos;
					else curImage = pos;
					
					//NSLog(@"Not volumic...");
					
					if( curImage >= [dcmPixList count]) curImage = [dcmPixList count] - 1;
					if( curImage < 0) curImage = 0;
				}
			}

			// Relative
			 if( syncro == syncroREL && point3D == NO && syncSeriesIndex == -1)
			 {
				if( flippedData) curImage -= diff;
				else curImage += diff;
				
				//NSLog(@"Rel");
				
				if( curImage < 0)
				{
					curImage += [dcmPixList count];
				}

				if( curImage >= [dcmPixList count]) curImage -= [dcmPixList count];
			 }
			
			// Relatif
			if( curImage != prevImage)
			{
				if( listType == 'i') [self setIndex:curImage];
				else [self setIndexWithReset:curImage :YES];
			}
			
			if( [[[self window] windowController] is2DViewer] == YES)
				[[[self window] windowController] adjustSlider];
			
			if( [oStudyId isEqualToString:[[dcmFilesList objectAtIndex:[self indexForPix:curImage]] valueForKeyPath:@"series.study.studyInstanceUID"]])
				{
					[self computeSlice: oPix :oPix2];
				}
				else
				{
					sliceVector2[0] = sliceVector2[1] = sliceVector2[2] = 0; 
					slicePoint2[0] = slicePoint2[1] = slicePoint2[2] = 0; 
				}
				
			[self setNeedsDisplay:YES];
		}
		else
		{
			sliceVector[0] = sliceVector[1] = sliceVector[2] = 0; 
			slicePoint[0] = slicePoint[1] = slicePoint[2] = 0;
			sliceVector2[0] = sliceVector2[1] = sliceVector2[2] = 0; 
			slicePoint2[0] = slicePoint2[1] = slicePoint2[2] = 0; 
		}
    }
	}
}

-(void) roiSelected:(NSNotification*) note
{
	NSArray *winList = [[NSApplication sharedApplication] windows];
	long	i;
	
	for( i = 0; i < [winList count]; i++)
	{
		if( [[[[winList objectAtIndex:i] windowController] windowNibName] isEqualToString:@"ROI"])
		{
			[[[winList objectAtIndex:i] windowController] setROI: [note object] :[[self window] windowController]];
		}
	}
}

-(void) roiChange:(NSNotification*)note
{
	long i;
	
	// A ROI changed... do we display it? If yes, update!
	for( i = 0; i < [curRoiList count]; i++)
	{
		if( [curRoiList objectAtIndex:i] == [note object])
		{
			[[note object] setRoiFont:labelFontListGL :labelFontListGLSize :self];
			[self setNeedsDisplay:YES];
		}
	}
}

-(void) updateView:(NSNotification*)note
{
    [self setNeedsDisplay:YES];
}

-(void) barMenu:(id) sender
{
    NSMenu   *menu = [sender menu];
    short    i;
    
    i = [menu numberOfItems];
    while(i-- > 0) [[menu itemAtIndex:i] setState:NSOffState];   
    
	[[NSUserDefaults standardUserDefaults] setInteger: [sender tag] forKey: @"CLUTBARS"];

    NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName: @"updateView" object: self userInfo: nil];
}

-(void) annotMenu:(id) sender
{
    NSMenu   *menu = [sender menu];
    short    i;
    
    i = [menu numberOfItems];
    while(i-- > 0) [[menu itemAtIndex:i] setState:NSOffState];   
    
	[[NSUserDefaults standardUserDefaults] setInteger: [sender tag] forKey: @"ANNOTATIONS"];
    
    NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName: @"updateView" object: self userInfo: nil];
}

-(void) setSyncro:(long) s
{
	syncro = s;
}

-(long) syncro
{
	return syncro;
}

-(void) syncronize:(id) sender
{
    NSMenu   *menu = [sender menu];
    short    i;
    
    i = [menu numberOfItems];
    while(i-- > 0) [[menu itemAtIndex:i] setState:NSOffState];   
    
    syncro = [sender tag];
    
    [sender setState:NSOnState];
	
//	if( [sender tag] == 4)
//	{
//		[[[self window] windowController] syncSetOffset];
//	}
}

-(void) FindMinimumOpenGLCapabilities
{
    long deviceMaxTextureSize = 0, NPOTDMaxTextureSize = 0;
    
    // init desired caps to max values
    f_ext_texture_rectangle = YES;
    f_arb_texture_rectangle = YES;
    f_ext_client_storage = YES;
    f_ext_packed_pixel = YES;
    f_ext_texture_edge_clamp = YES;
    f_gl_texture_edge_clamp = YES;
    maxTextureSize = 0x7FFFFFFF;
    maxNOPTDTextureSize = 0x7FFFFFFF;
    
    // get strings
    enum { kShortVersionLength = 32 };
    const GLubyte * strVersion = glGetString (GL_VERSION); // get version string
    const GLubyte * strExtension = glGetString (GL_EXTENSIONS);	// get extension string
    
    // get just the non-vendor specific part of version string
    GLubyte strShortVersion [kShortVersionLength];
    short i = 0;
    while ((((strVersion[i] <= '9') && (strVersion[i] >= '0')) || (strVersion[i] == '.')) && (i < kShortVersionLength)) // get only basic version info (until first space)
            strShortVersion [i] = strVersion[i++];
    strShortVersion [i] = 0; //truncate string
    
    // compare capabilities based on extension string and GL version
    f_ext_texture_rectangle = 
            f_ext_texture_rectangle && strstr ((const char *) strExtension, "GL_EXT_texture_rectangle");
    f_arb_texture_rectangle = 
            f_arb_texture_rectangle && strstr ((const char *) strExtension, "GL_ARB_texture_rectangle");
    f_ext_client_storage = 
            f_ext_client_storage && strstr ((const char *) strExtension, "GL_APPLE_client_storage");
    f_ext_packed_pixel = 
            f_ext_packed_pixel && strstr ((const char *) strExtension, "GL_APPLE_packed_pixel");
    f_ext_texture_edge_clamp = 
            f_ext_texture_edge_clamp && strstr ((const char *) strExtension, "GL_SGIS_texture_edge_clamp");
    f_gl_texture_edge_clamp = 
            f_gl_texture_edge_clamp && (!strstr ((const char *) strShortVersion, "1.0") && !strstr ((const char *) strShortVersion, "1.1")); // if not 1.0 and not 1.1 must be 1.2 or greater
    
    // get device max texture size
    glGetIntegerv (GL_MAX_TEXTURE_SIZE, &deviceMaxTextureSize);
    if (deviceMaxTextureSize < maxTextureSize)
            maxTextureSize = deviceMaxTextureSize;
    // get max size of non-power of two texture on devices which support
    if (NULL != strstr ((const char *) strExtension, "GL_EXT_texture_rectangle"))
    {
    #ifdef GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT
            glGetIntegerv (GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT, &NPOTDMaxTextureSize);
            if (NPOTDMaxTextureSize < maxNOPTDTextureSize)
                    maxNOPTDTextureSize = NPOTDMaxTextureSize;
	#endif
    }
	
//			maxTextureSize = 500;
	
    // set clamp param based on retrieved capabilities
    if (f_gl_texture_edge_clamp) // if OpenGL 1.2 or later and texture edge clamp is supported natively
                            edgeClampParam = GL_CLAMP_TO_EDGE;  // use 1.2+ constant to clamp texture coords so as to not sample the border color
    else if (f_ext_texture_edge_clamp) // if GL_SGIS_texture_edge_clamp extension supported
            edgeClampParam = GL_CLAMP_TO_EDGE_SGIS; // use extension to clamp texture coords so as to not sample the border color
    else
            edgeClampParam = GL_CLAMP; // clamp texture coords to [0, 1]
			
	if( f_arb_texture_rectangle && f_ext_texture_rectangle)
	{
//		NSLog(@"ARB Rectangular Texturing!");
		TEXTRECTMODE = GL_TEXTURE_RECTANGLE_ARB;
		maxTextureSize = maxNOPTDTextureSize;
	}
	else
	if( f_ext_texture_rectangle)
	{
//		NSLog(@"Rectangular Texturing!");
		TEXTRECTMODE = GL_TEXTURE_RECTANGLE_EXT;
		maxTextureSize = maxNOPTDTextureSize;
	}
	else
	{
		TEXTRECTMODE = GL_TEXTURE_2D;
	}
	
}

-(void) setCrossCoordinatesPer:(float) val
{
	cross.x -= val*cos(angle);
	cross.y -= val*sin(angle);
	
	[self setNeedsDisplay: YES];
}

-(void) getCrossCoordinates:(float*) x: (float*) y
{
	*x = cross.x;
	*y = -cross.y;
}

-(void) setCrossCoordinates:(float) x :(float) y :(BOOL) update
{
	cross.x =  x;
	cross.y = -y;
	
	[self setNeedsDisplay: YES];
	
	if( update)
		[[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object: stringID userInfo: [NSDictionary dictionaryWithObject:@"set" forKey:@"action"]];
}

-(void) setCross:(long) x :(long) y :(BOOL) update
{
	NSRect      size = [self frame];
    
	cross.x = x + size.size.width/2;
	cross.y = y + size.size.height/2;
	
	cross.y = size.size.height - cross.y ;
	cross = [self ConvertFromView2GL:cross];
	
	[self setNeedsDisplay:true];
	
	if( update)
		[[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object: stringID userInfo: [NSDictionary dictionaryWithObject:@"set" forKey:@"action"]];
}

-(void) setMPRAngle: (float) vectorMPR
{
	angle = vectorMPR;
	mprVector[ 0] = cos(vectorMPR*deg2rad);
	mprVector[ 1] = sin(vectorMPR*deg2rad);
				
	[self setNeedsDisplay:true];
}

-(float) angle { return angle;}

- (NSPoint) cross
{
	return cross;
}

- (NSPoint) crossPrev
{
	return crossPrev;
}

- (void) setCrossPrev:(NSPoint) c
{
	crossPrev = c;
}

-(void) cross3D:(float*) x :(float*) y :(float*) z 
{
	NSPoint cPt = cross;	//[self ConvertFromView2GL:cross];

//	cPt.x += [curDCM pwidth]/2.;
//	cPt.y += [curDCM pheight]/2.;
	
	if( x) *x = cPt.x * [[dcmPixList objectAtIndex:0] pixelSpacingX];
	if( y) *y = cPt.y * [[dcmPixList objectAtIndex:0] pixelSpacingY];
	
//	if( [curDCM sliceThickness] < 0) NSLog(@"thickness NEG");
	if( z) *z = curImage;  //* [curDCM sliceThickness];
//	*z =  [curDCM sliceLocation];
	
	// Now convert this local point in a global 3D coordinate!
	
	float temp[ 3], vectorB[ 9];
	
//	*x += [curDCM originX];
//	*y += [curDCM originY];
//	*z += [curDCM originZ];

//	[curDCM orientation: vectorB];

//	temp[ 0] = *x * vectorB[ 0] + *y * vectorB[ 1] + *z * vectorB[ 2];
//	temp[ 1] = *x * vectorB[ 3] + *y * vectorB[ 4] + *z * vectorB[ 5];
//	temp[ 2] = *x * vectorB[ 6] + *y * vectorB[ 7] + *z * vectorB[ 8];
//	
//	*x = temp[ 0];
//	*y = temp[ 1];
//	*z = temp[ 2];
	
//	*x =  temp[ 0];
//	*y =  temp[ 1];
//	*z =  temp[ 2];

//	*x -= [curDCM originX];
//	*y -= [curDCM originY];
//	*z -= [curDCM originZ];
	
//	NSLog(@"3D Pt: X=%0.0f Y=%0.0f Z=%0.0f", *x, *y, *z);

}

-(NSPoint) rotatePoint:(NSPoint) a
{
    float xx, yy;
    NSRect size = [self frame];
    
	if( xFlipped) a.x = size.size.width - a.x;
	if( yFlipped) a.y = size.size.height - a.y;
	
    a.x -= size.size.width/2;
//    a.x /= scaleValue;
	
    a.y -= size.size.height/2;
  //  a.y /= scaleValue;
    
    xx = a.x*cos(rotation*deg2rad) + a.y*sin(rotation*deg2rad);
    yy = -a.x*sin(rotation*deg2rad) + a.y*cos(rotation*deg2rad);
    
    a.y = yy;
    a.x = xx;

    a.x -= (origin.x + originOffset.x);
    a.y += (origin.y + originOffset.y);

	a.x += [curDCM pwidth]/2.;
	a.y += [curDCM pheight]/ 2.;
	
    return a;
}

-(NSPoint) ConvertFromGL2View:(NSPoint) a
{
    float xx, yy;
    NSRect size = [self frame];
	
	if( curDCM)
	{
		a.y *= [curDCM pixelRatio];
		a.y -= [curDCM pheight]*[curDCM pixelRatio]/ 2.;
		a.x -= [curDCM pwidth]/2.;
	}
	
	a.y -= (origin.y + originOffset.y)/scaleValue;
	a.x += (origin.x + originOffset.x)/scaleValue;

    xx = a.x*cos(-rotation*deg2rad) + a.y*sin(-rotation*deg2rad);
    yy = -a.x*sin(-rotation*deg2rad) + a.y*cos(-rotation*deg2rad);

    a.y = yy;
    a.x = xx;

    a.y *= scaleValue;
	a.y += size.size.height/2;
	
    a.x *= scaleValue;
	a.x += size.size.width/2;
	
	if( xFlipped) a.x = size.size.width - a.x;
	if( yFlipped) a.y = size.size.height - a.y;
	
	a.x -= size.size.width/2;
	a.y -= size.size.height/2;
	
    return a;
}

-(NSPoint) ConvertFromView2GL:(NSPoint) a
{
    float xx, yy;
    NSRect size = [self frame];
    
	if( xFlipped) a.x = size.size.width - a.x;
	if( yFlipped) a.y = size.size.height - a.y;
	
    a.x -= size.size.width/2;
    a.x /= scaleValue;
	
    a.y -= size.size.height/2;
    a.y /= scaleValue;
    
    xx = a.x*cos(rotation*deg2rad) + a.y*sin(rotation*deg2rad);
    yy = -a.x*sin(rotation*deg2rad) + a.y*cos(rotation*deg2rad);
    
    a.y = yy;
    a.x = xx;

    a.x -= (origin.x + originOffset.x)/scaleValue;
    a.y += (origin.y + originOffset.y)/scaleValue;
    
	if( curDCM)
	{
		a.x += [curDCM pwidth]/2.;
		a.y += [curDCM pheight]*[curDCM pixelRatio]/ 2.;
		a.y /= [curDCM pixelRatio];
    }
    return a;
}

- (void) setQuartzExtreme:(BOOL) set
{
	if( set != QuartzExtreme)
	{
		QuartzExtreme = set;
		
		if( QuartzExtreme)		// ACTIVATE
		{
			long negativeOne = -1;
			[[self openGLContext] setValues:&negativeOne forParameter:NSOpenGLCPSurfaceOrder];
			[[self window] setOpaque:NO];
			[[self window] setAlphaValue:.999f];
		}
		else					// DE-ACTIVATE
		{
			long negativeOne = 1;
			[[self openGLContext] setValues:&negativeOne forParameter:NSOpenGLCPSurfaceOrder];
			[[self window] setOpaque:YES];
			[[self window] setAlphaValue:1.0f];
		}
	}
}

- (void) drawRectIn:(NSRect) size :(GLuint *) texture :(NSPoint) offset :(long) tX :(long) tY
{
	if( mainThread != [NSThread currentThread])
	{
		NSLog(@"Warning! OpenGL activity NOT in the main thread???");
	}
	
	long effectiveTextureMod = 0; // texture size modification (inset) to account for borders
	long x, y, k = 0, offsetY, offsetX = 0, currTextureWidth, currTextureHeight;

    glMatrixMode (GL_MODELVIEW);
    glLoadIdentity ();
	
	glDepthMask (GL_TRUE);
	
	glScalef (2.0f /(xFlipped ? -(size.size.width) : size.size.width), -2.0f / (yFlipped ? -(size.size.height) : size.size.height), 1.0f); // scale to port per pixel scale
	glRotatef (rotation, 0.0f, 0.0f, 1.0f); // rotate matrix for image rotation
	glTranslatef( origin.x - offset.x + originOffset.x, -origin.y - offset.y - originOffset.y, 0.0f);
	
//	NSLog( @"%f %f", origin.x, origin.y);
//	NSLog( @"%f %f", offset.x, offset.y);
//	NSLog( @"%f %f", originOffset.x, originOffset.y);
	
	if( [curDCM pixelRatio] != 1.0)
	{
		glScalef( 1.f, [curDCM pixelRatio], 1.f);
	}
	
	effectiveTextureMod = 0;	//2;	//OVERLAP
	
	glEnable (TEXTRECTMODE); // enable texturing
	glColor4f (1.0f, 1.0f, 1.0f, 1.0f); 
	
	for (x = 0; x < tX; x++) // for all horizontal textures
	{
			// use remaining to determine next texture size
			currTextureWidth = GetNextTextureSize (textureWidth - offsetX, maxTextureSize, f_ext_texture_rectangle) - effectiveTextureMod; // current effective texture width for drawing
			offsetY = 0; // start at top
			for (y = 0; y < tY; y++) // for a complete column
			{
					// use remaining to determine next texture size
					currTextureHeight = GetNextTextureSize (textureHeight - offsetY, maxTextureSize, f_ext_texture_rectangle) - effectiveTextureMod; // effective texture height for drawing
					glBindTexture(TEXTRECTMODE, texture[k++]); // work through textures in same order as stored, setting each texture name as current in turn
					DrawGLImageTile (GL_TRIANGLE_STRIP, [curDCM pwidth], [curDCM pheight], (scaleValue),		//
										currTextureWidth, currTextureHeight, // draw this single texture on two tris 
										offsetX,  offsetY, 
										currTextureWidth + offsetX, 
										currTextureHeight + offsetY, 
										false, f_ext_texture_rectangle);		// OVERLAP
					offsetY += currTextureHeight; // offset drawing position for next texture vertically
			}
			offsetX += currTextureWidth; // offset drawing position for next texture horizontally
	}
	
    glDisable (TEXTRECTMODE); // done with texturing
}

-(float) pixelSpacing
{
	return [curDCM pixelSpacingX];
}

- (float) pixelSpacingX
{
	return [curDCM pixelSpacingX];
}

- (float) pixelSpacingY
{
	return [curDCM pixelSpacingY];
}

- (DCMPix*) curDCM { return curDCM;}

- (void) getOrientationText:(char *) orientation : (float *) vector :(BOOL) inv
{
	char orientationX;
	char orientationY;
	char orientationZ;

	char *optr = orientation;
	*optr = 0;
	
	if( inv)
	{
		orientationX = -vector[ 0] < 0 ? 'R' : 'L';
		orientationY = -vector[ 1] < 0 ? 'A' : 'P';
		orientationZ = -vector[ 2] < 0 ? 'F' : 'H';
	}
	else
	{
		orientationX = vector[ 0] < 0 ? 'R' : 'L';
		orientationY = vector[ 1] < 0 ? 'A' : 'P';
		orientationZ = vector[ 2] < 0 ? 'F' : 'H';
	}
	
	float absX = fabs( vector[ 0]);
	float absY = fabs( vector[ 1]);
	float absZ = fabs( vector[ 2]);
	
	int i; 
	for (i=0; i<1; ++i)
	{
		if (absX>.0001 && absX>absY && absX>absZ)
		{
			*optr++=orientationX; absX=0;
		}
		else if (absY>.0001 && absY>absX && absY>absZ)
		{
			*optr++=orientationY; absY=0;
		} else if (absZ>.0001 && absZ>absX && absZ>absY)
		{
			*optr++=orientationZ; absZ=0;
		} else break; *optr='\0';
	}
}

//- (void) drawRect:(NSRect)aRect
//{
//	long i;
//    [[self openGLContext] makeCurrentContext];
//		glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
//			// init GL stuff here
//	glEnable(GL_DEPTH_TEST);
//
//	glShadeModel(GL_SMOOTH);    
//	glEnable(GL_CULL_FACE);
//	glFrontFace(GL_CCW);
//	glPolygonOffset (1.0f, 1.0f);
//	
//	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
//
//			for( i = 0; i < [curRoiList count]; i++)
//		{
//			[[curRoiList objectAtIndex:i] drawROI: scaleValue :[curDCM pwidth]/2. :[curDCM pheight]/2. :[curDCM pixelSpacingX]];
//		}
//		
//	[[self openGLContext] flushBuffer];
//}

-(void) setSlab:(float)s
{
	slab = s;
	
	[self setNeedsDisplay:true];
}

// Copyright 2001, softSurfer (www.softsurfer.com)
// This code may be freely used and modified for any purpose
// providing that this copyright notice is included with it.
// SoftSurfer makes no warranty for this code, and cannot be held
// liable for any real or imagined damage resulting from its use.
// Users of this code must verify correctness for their application.

// Assume that classes are already given for the objects:
//    Point and Vector with
//        coordinates {float x, y, z;}
//        operators for:
//            Point  = Point � Vector
//            Vector = Point - Point
//            Vector = Scalar * Vector    (scalar product)
//    Plane with a point and a normal {Point V0; Vector n;}
//===================================================================

// dot product (3D) which allows vector operations in arguments

#define dot(u,v)   ((u)[0] * (v)[0] + (u)[1] * (v)[1] + (u)[2] * (v)[2])
#define norm(v)    sqrt(dot(v,v))  // norm = length of vector
#define d(u,v)     norm(u-v)       // distance = norm of difference

// pbase_Plane(): get base of perpendicular from point to a plane
//    Input:  P = a 3D point
//            PL = a plane with point V0 and normal n
//    Output: *B = base point on PL of perpendicular from P
//    Return: the distance from P to the plane PL

- (float) pbase_Plane: (float*) point :(float*) planeOrigin :(float*) planeVector :(float*) pointProjection
{
    float	sb, sn, sd;
	float	sub[ 3];
	
	sub[ 0] = point[ 0] - planeOrigin[ 0];
	sub[ 1] = point[ 1] - planeOrigin[ 1];
	sub[ 2] = point[ 2] - planeOrigin[ 2];
	
    sn = -dot( planeVector, sub);
    sd = dot( planeVector, planeVector);
    sb = sn / sd;
	
	pointProjection[ 0] = point[ 0] + sb * planeVector[ 0];
	pointProjection[ 1] = point[ 1] + sb * planeVector[ 1];
	pointProjection[ 2] = point[ 2] + sb * planeVector[ 2];
	
	sub[ 0] = point[ 0] - pointProjection[ 0];
	sub[ 1] = point[ 1] - pointProjection[ 1];
	sub[ 2] = point[ 2] - pointProjection[ 2];

    return norm( sub);
}
//===================================================================

- (long) findPlaneAndPoint:(float*) pt :(float*) location
{
	long	i, ii = -1;
	float	vectors[ 9], orig[ 3], locationTemp[ 3];
	float	distance = 999999, tempDistance;
	
	for( i = 0; i < [dcmPixList count]; i++)
	{
		[[dcmPixList objectAtIndex: i] orientation: vectors];
		
		orig[ 0] = [[dcmPixList objectAtIndex: i] originX];
		orig[ 1] = [[dcmPixList objectAtIndex: i] originY];
		orig[ 2] = [[dcmPixList objectAtIndex: i] originZ];
		
		tempDistance = [self pbase_Plane: pt :orig :&(vectors[ 6]) :locationTemp];
		
		if( tempDistance < distance)
		{
			location[ 0] = locationTemp[ 0];
			location[ 1] = locationTemp[ 1];
			location[ 2] = locationTemp[ 2];
			distance = tempDistance;
			ii = i;
		}
	}
	
	if( ii != -1)
	{
		NSLog(@"Distance: %2.2f, Index: %d", distance, ii);
		
		if( distance > [curDCM sliceThickness] * 2) ii = -1;
	}
	
	return ii;
}

- (void) drawOrientation:(NSRect) size
{
	// Determine Anterior, Posterior, Left, Right, Head, Foot
	char	string[ 10];
	float   vectors[ 9];
	float	rot = rotation;
	
	[curDCM orientation:vectors];
	
	[self getOrientationText:string :vectors :YES];
	//left side
	if(rot >= 0 && rot <= 45)  {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
	}
	
	else if (rot >= 315 && rot <= 360) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
	 }
	//top
	else if (rot >= 45 && rot <= 135) {
		if (yFlipped) 
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
	}
	//right
	else if(rot >= 135 && rot <= 225) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
	}
	// bottom
	else if(rot >= 225 && rot <= 315) {
		if (yFlipped) 
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
	}
	[self getOrientationText:string :vectors :NO];
	// right
	if(rot >= 0 && rot <= 45)	{
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
	}
	else if(rot >= 315 && rot <= 360){
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
	}
	//bottom
	else if(rot >= 45 && rot <= 135) {
		if (yFlipped) 
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
	}
	//left
	else if(rot >= 135 && rot <= 225) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
	}
	//top
	else if(rot >= 225 && rot <= 315) {
		if (yFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
	}

	[self getOrientationText:string :vectors+3 :YES];
	//top
	if(rot >= 0 && rot <= 45) {
		if (yFlipped)
			 [self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
	}
	else if(rot >= 315 && rot <= 360) {
		if (yFlipped)
			 [self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
	}
	//right
	else if(rot >= 45 && rot <= 135) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
	}
	//bottom
	else if(rot >= 135 && rot <= 225) {
		if (yFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
	}
	//left
	else if(rot >= 225 && rot <= 315) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
	}

	[self getOrientationText:string :vectors+3 :NO];
	//bottom
	if (rot >= 0 && rot <= 45)	{
		if (yFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
	}
	else if (rot >= 315 && rot <= 360) {
		if (yFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
	}
	// left
	else if(rot >= 45 && rot <= 135){
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
	}
	// top
	else if (rot >= 135 && rot <= 225) {
		if (yFlipped)
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :2+size.size.height-2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width/2 :12];
	}
	//right
	else if (rot >= 225 && rot <= 315) {
		if 	(xFlipped)
			[self DrawCStringGL: string : labelFontListGL :2 :2+size.size.height/2];
		else
			[self DrawCStringGL: string : labelFontListGL :size.size.width-10 :2+size.size.height/2];
	}
}

- (void) drawTextualData:(NSRect) size :(long) annotations
{
	long		yRaster = 1, xRaster;
	BOOL		fullText = YES;
	NSString	*tempString;
		
	//** TEXT INFORMATION
	glLoadIdentity (); // reset model view matrix to identity (eliminates rotation basically)
	glScalef (2.0f / size.size.width, -2.0f /  size.size.height, 1.0f); // scale to port per pixel scale
	glTranslatef (-(size.size.width) / 2.0f, -(size.size.height) / 2.0f, 0.0f); // translate center to upper left
	
	//draw line around edge for key Images only in 2D Viewer
	
	if ([[[self window] windowController] isMemberOfClass:[ViewerController class]] && [[[self window] windowController] isKeyImage:curImage]) {
		glLineWidth(2.0);
		glColor3f (1.0f, 1.0f, 0.0f);
		glBegin(GL_LINE_LOOP);
			glVertex2f(1.0,                                      1.0);
			glVertex2f(1.0,                   size.size.height - 1.0);
			glVertex2f(size.size.width - 1.0, size.size.height - 1.0);
			glVertex2f(size.size.width - 1.0,                    1.0);
		glEnd();
	}
		
	
	glColor3f (0.0f, 0.0f, 0.0f);
//	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glLineWidth(1.0);
	
	if( stringID && [stringID isEqualToString:@"OrthogonalMPRVIEW"] == YES)
	{
		fullText = NO;
		
		if( isKeyView == NO)
		{
			[self drawOrientation:size];
			return;
		}
	}
	
	if( fullText)
	{
		tempString = [NSString stringWithFormat: @"Image size: %ld x %ld", (long) [curDCM pwidth], (long) [curDCM pheight]];
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height rightAlignment: NO useStringTexture: YES];
		
		tempString = [NSString stringWithFormat: @"View size: %ld x %ld", (long) size.size.width, (long) size.size.height];
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
	}
	
	if( mouseXPos != 0 && mouseYPos != 0)
	{
		if( [curDCM isRGB]) tempString = [NSString stringWithFormat: @"X: %d px Y: %d px Value: R:%ld G:%ld B:%ld", (int)mouseXPos, (int)mouseYPos, pixelMouseValueR, pixelMouseValueG, pixelMouseValueB];
		else tempString = [NSString stringWithFormat: @"X: %d px Y: %d px Value: %2.2f", (int)mouseXPos, (int)mouseYPos, pixelMouseValue];
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
		
		if( blendingView)
		{
			if( [[blendingView curDCM] isRGB]) tempString = [NSString stringWithFormat: @"Fused Image : X: %d px Y: %d px Value: R:%ld G:%ld B:%ld", (int)blendingMouseXPos, (int)blendingMouseYPos, blendingPixelMouseValueR, blendingPixelMouseValueG, blendingPixelMouseValueB];
			else tempString = [NSString stringWithFormat: @"Fused Image : X: %d px Y: %d px Value: %2.2f", (int)blendingMouseXPos, (int)blendingMouseYPos, blendingPixelMouseValue];
			[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
		}
		
		if( [curDCM displaySUVValue])
		{
			if( [curDCM hasSUV] == YES && [curDCM SUVConverted] == NO)
			{
				tempString = [NSString stringWithFormat: @"SUV: %.2f", [self getSUV]];
				[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
			}
		}
		
		if( blendingView)
		{
			if( [[blendingView curDCM] displaySUVValue] && [[blendingView curDCM] hasSUV] && [[blendingView curDCM] SUVConverted] == NO)
			{
				tempString = [NSString stringWithFormat: @"SUV (fused image): %.2f", [self getBlendedSUV]];
				[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
			}
		}
	}
	
	float	lwl, lww;
	
	if( [stringID isEqualToString:@"MPR3D"])
	{
		[[[self window] windowController] getWLWW:&lwl :&lww];
	}
	else
	{
		lwl = [curDCM wl];
		lww = [curDCM ww];
	}
	
//	if( fullText)
	{
		if( lww < 50) tempString = [NSString stringWithFormat: @"WL: %0.4f WW: %0.4f", lwl, lww];
		else tempString = [NSString stringWithFormat: @"WL: %ld WW: %ld", (long) lwl, (long) lww];
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
		
		if( [[[dcmFilesList objectAtIndex: 0] valueForKey:@"modality"] isEqualToString:@"PT"]  == YES)// && [[[self window] windowController] is2DViewer] == YES)
		{
			if( [curDCM maxValueOfSeries])
			{
				float min = lwl - lww/2, max = lwl + lww/2;
				
				tempString = [NSString stringWithFormat: @"From: %d %% (%0.2f) to: %d %% (%0.2f)", (long) (min * 100. / [curDCM maxValueOfSeries]), lwl - lww/2, (long) (max * 100. / [curDCM maxValueOfSeries]), lwl + lww/2];
				[self DrawNSStringGL: tempString : fontListGL :4 :yRaster++ * stringSize.height];
			}
		}
		
	}		
	// Draw any additional plugin text information
	{
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithFloat: yRaster++ * stringSize.height], @"yPos", nil];
		
		[[NSNotificationCenter defaultCenter] postNotificationName: @"PLUGINdrawTextInfo"
															object: self
														  userInfo: userInfo];
	}
	
	
	// BOTTOM LEFT
	
	yRaster = size.size.height-2;
	
	if( stringID == 0L || [stringID isEqualToString:@"OrthogonalMPRVIEW"] || [stringID isEqualToString:@"FinalView"])
	{
		if( mouseXPos != 0 && mouseYPos != 0)
		{
			float location[ 3 ];
			
			if( [curDCM stack] > 1)
			{
				long maxVal;
			
				if( flippedData) maxVal = curImage-([curDCM stack]-1)/2;
				else maxVal = curImage+([curDCM stack]-1)/2;
				
				if( maxVal < 0) maxVal = 0;
				if( maxVal >= [dcmPixList count]) maxVal = [dcmPixList count]-1;
				
				[[dcmPixList objectAtIndex: maxVal] convertPixX: mouseXPos pixY: mouseYPos toDICOMCoords: location];
			}
			else
			{
				[curDCM convertPixX: mouseXPos pixY: mouseYPos toDICOMCoords: location];
			}
			
			if(fabs(location[0]) < 1.0 && location[0] != 0.0)
				tempString = [NSString stringWithFormat: @"X: %2.2f %cm Y: %2.2f %cm Z: %2.2f %cm", location[0] * 1000.0, 0xB5, location[1] * 1000.0, 0xB5, location[2] * 1000.0, 0xB5];
			else
				tempString = [NSString stringWithFormat: @"X: %2.2f mm Y: %2.2f mm Z: %2.2f mm", location[0], location[1], location[2]];
			
			[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
			yRaster -= stringSize.height;
		}
	}
	
	// Thickness
	if( [curDCM sliceThickness] != 0 && [curDCM sliceLocation] != 0)
	{
		if( [curDCM stack] > 1)
		{
			long maxVal;
			
			if( flippedData) maxVal = curImage-[curDCM stack];
			else maxVal = curImage+[curDCM stack];
			
			if( maxVal < 0) maxVal = curImage;
			else if( maxVal > [dcmPixList count]) maxVal = [dcmPixList count] - curImage;
			else maxVal = [curDCM stack];
			
			float vv = fabs( (maxVal-1) * [[dcmPixList objectAtIndex:0] sliceInterval]);
			
			vv += [curDCM sliceThickness];
			
			float pp;
			
			if( flippedData)
			{
				pp = ([[dcmPixList objectAtIndex: curImage] sliceLocation] + [[dcmPixList objectAtIndex: curImage - maxVal+1] sliceLocation])/2.;
			}
			else
				pp = ([[dcmPixList objectAtIndex: curImage] sliceLocation] + [[dcmPixList objectAtIndex: curImage + maxVal-1] sliceLocation])/2.;
				
			if( vv < 1.0 && vv != 0.0)
			{
				if( fabs( pp) < 1.0 && pp != 0.0)
					tempString = [NSString stringWithFormat: @"Thickness: %0.2f %cm Location: %0.2f %cm", fabs( vv * 1000.0), 0xB5, pp * 1000.0, 0xB5];
				else
					tempString = [NSString stringWithFormat: @"Thickness: %0.2f %cm Location: %0.2f mm", fabs( vv * 1000.0), 0xB5, pp];
			}
			else
				tempString = [NSString stringWithFormat: @"Thickness: %0.2f mm Location: %0.2f mm", fabs( vv), pp];
			
			[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
			yRaster -= stringSize.height;
		}
		else if( fullText)
		{
			if ([curDCM sliceThickness] < 1.0 && [curDCM sliceThickness] != 0.0)
			{
				if( fabs( [curDCM sliceLocation]) < 1.0 && [curDCM sliceLocation] != 0.0)
					tempString = [NSString stringWithFormat: @"Thickness: %0.2f %cm Location: %0.2f %cm", [curDCM sliceThickness] * 1000.0, 0xB5, [curDCM sliceLocation] * 1000.0, 0xB5];
				else
					tempString = [NSString stringWithFormat: @"Thickness: %0.2f %cm Location: %0.2f mm", [curDCM sliceThickness] * 1000.0, 0xB5, [curDCM sliceLocation]];
			}
			else
				tempString = [NSString stringWithFormat: @"Thickness: %0.2f mm Location: %0.2f mm", [curDCM sliceThickness], [curDCM sliceLocation]];
			
			[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
			yRaster -= stringSize.height;
		}
	} 
	else if( [curDCM viewPosition] || [curDCM patientPosition])	 
	{	 
		 NSString        *nsstring = 0L;	 

		 if( [curDCM viewPosition]) nsstring = [NSString stringWithFormat: @"Position: %@ ", [curDCM viewPosition]];	 
		 if( [curDCM patientPosition])	 
		 {	 
			if( nsstring) nsstring = [nsstring stringByAppendingString: [curDCM patientPosition]];	 
			else nsstring = [NSString stringWithFormat: @"Position: %@ ", [curDCM patientPosition]];	 
		 }	 

		 // Position
		 [self DrawNSStringGL: nsstring : fontListGL :4 :yRaster rightAlignment: NO useStringTexture: YES];
		 yRaster -= stringSize.height;	 
	}
	
	if( fullText)
	{
		// Zoom
		tempString = [NSString stringWithFormat: @"Zoom: %0.0f%% Angle: %0.0f", (float) scaleValue*100.0, (float) ((long) rotation % 360)];
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
		yRaster -= stringSize.height;
	}
	
	// Image Position
	
	if( [curDCM stack] > 1)
	{
		long maxVal;
		
		if( flippedData) maxVal = curImage-[curDCM stack]+1;
		else maxVal = curImage+[curDCM stack];
		
		if( maxVal < 0) maxVal = 0;
		if( maxVal > [dcmPixList count]) maxVal = [dcmPixList count];
		
		if( flippedData) tempString = [NSString stringWithFormat: @"Im: %ld-%ld/%ld", (long) [dcmPixList count] - curImage, [dcmPixList count] - maxVal, (long) [dcmPixList count]];
		else tempString = [NSString stringWithFormat: @"Im: %ld-%ld/%ld", (long) curImage+1, maxVal, (long) [dcmPixList count]];
		
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
		yRaster -= stringSize.height;
	} 
	else if( fullText)
	{
		if( flippedData) tempString = [NSString stringWithFormat: @"Im: %ld/%ld", (long) [dcmPixList count] - curImage, (long) [dcmPixList count]];
		else tempString = [NSString stringWithFormat: @"Im: %ld/%ld", (long) curImage+1, (long) [dcmPixList count]];
		
		[self DrawNSStringGL: tempString : fontListGL :4 :yRaster];
		yRaster -= stringSize.height;
	}
	
	[self drawOrientation: size];
	
	// More informations
	
	//yRaster = 1;
	yRaster = 0; //absolute value for yRaster;
	NSManagedObject   *file;

	file = [dcmFilesList objectAtIndex:[self indexForPix:curImage]];
	if( annotations >= annotFull && fullText)
	{
		if( [file valueForKeyPath:@"series.study.name"])
		{
			NSString	*nsstring;
			
			if( [file valueForKeyPath:@"series.study.dateOfBirth"])
			{
				nsstring = [NSString stringWithFormat: @"%@ - %@ - %@",[file valueForKeyPath:@"series.study.name"], [[file valueForKeyPath:@"series.study.dateOfBirth"] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary], yearOld];
			}
			else  nsstring = [file valueForKeyPath:@"series.study.name"];
			
			xRaster = size.size.width;
			[self DrawNSStringGL: nsstring : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		if( [file valueForKeyPath:@"series.study.patientID"])
		{
			xRaster = size.size.width;
			[self DrawNSStringGL: [file valueForKeyPath:@"series.study.patientID"] : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
	} //annotations >= annotFull
	
	if( annotations >= annotBase && fullText)
	{
		if( [file valueForKeyPath:@"series.study.studyName"])
		{
			xRaster = size.size.width;// - ([self lengthOfString:string forFont:fontListGLSize] + 2);
			[self DrawNSStringGL: [file valueForKeyPath:@"series.study.studyName"] : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		if( [file valueForKeyPath:@"series.study.id"])
		{
			xRaster = size.size.width;// - ([self lengthOfString:string forFont:fontListGLSize] + 2);		
			[self DrawNSStringGL: [file valueForKeyPath:@"series.study.id"] : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		if( [file valueForKeyPath:@"series.id"])
		{
			xRaster = size.size.width;
			[self DrawNSStringGL: [[file valueForKeyPath:@"series.id"] stringValue] : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		if( [curDCM echotime] != 0L &&  [curDCM repetitiontime] != 0L) 
		{
			float repetitiontime = [[curDCM repetitiontime] floatValue];
			float echotime = [[curDCM echotime] floatValue];
			tempString = [NSString stringWithFormat:@"TR: %.2f, TE: %.2f", repetitiontime, echotime];
			xRaster = size.size.width;// - ([self lengthOfString:cptr forFont:fontListGLSize] + 2);		
			[self DrawNSStringGL: tempString : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		if( [curDCM protocolName] != 0L)
		{
			xRaster = size.size.width;// - ([self lengthOfString:string forFont:fontListGLSize] + 2);		
			[self DrawNSStringGL: [curDCM protocolName] : fontListGL :xRaster :yRaster + stringSize.height rightAlignment: YES useStringTexture: YES];
			yRaster += (stringSize.height + stringSize.height/10);
		}
		
		yRaster = size.size.height-2;
		xRaster = size.size.width;
		[self DrawNSStringGL: @"Made In OsiriX" : fontListGL :xRaster :yRaster rightAlignment: YES useStringTexture: YES];
		yRaster -= (stringSize.height + stringSize.height/10);
		
		NSCalendarDate  *date = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: [[file valueForKey:@"date"] timeIntervalSinceReferenceDate]];
		if( date && [date yearOfCommonEra] != 3000)
		{
			tempString = [date descriptionWithCalendarFormat: [[NSUserDefaults standardUserDefaults] objectForKey: NSShortDateFormatString]];	//	DDP localized from "%a %m/%d/%Y" 
			xRaster = size.size.width;// - ([self lengthOfString:cptr forFont:fontListGLSize] + 2);		
			[self DrawNSStringGL: tempString : fontListGL :xRaster :yRaster rightAlignment: YES useStringTexture: YES];
			yRaster -= (stringSize.height + stringSize.height/10);
		}
		//yRaster -= 12;
		
		if( [curDCM acquisitionTime]) date = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate: [[curDCM acquisitionTime] timeIntervalSinceReferenceDate]];
		if( date && [date yearOfCommonEra] != 3000)
		{
			tempString = [date descriptionWithCalendarFormat: [[NSUserDefaults standardUserDefaults] objectForKey: NSTimeFormatString]];	//	DDP localized from "%I:%M %p" 
			xRaster = size.size.width;// - ([self lengthOfString:cptr forFont:fontListGLSize] + 2);		
			[self DrawNSStringGL: tempString : fontListGL :xRaster :yRaster rightAlignment: YES useStringTexture: NO];
			yRaster -= (stringSize.height + stringSize.height/10);
		}
	}
//	yRaster -= 12;
}

- (void) applyImageTransformation
{
	NSSize size = [self frame].size;
	
	glLoadIdentity ();
	glViewport(0, 0, size.width, size.height);

	glScalef (2.0f /(xFlipped ? -(size.width) : size.width), -2.0f / (yFlipped ? -(size.height) : size.height), 1.0f);
	glRotatef (rotation, 0.0f, 0.0f, 1.0f);
	glTranslatef( origin.x + originOffset.x, -origin.y - originOffset.y, 0.0f);
	glScalef( 1.f, [curDCM pixelRatio], 1.f);
}

- (void) drawRect:(NSRect)aRect
{
	long		clutBars	= [[NSUserDefaults standardUserDefaults] integerForKey: @"CLUTBARS"];
	long		annotations	= [[NSUserDefaults standardUserDefaults] integerForKey: @"ANNOTATIONS"];
	
	if( noScale)
	{
		//scaleValue = 1;
		[self setScaleValue:1];
		origin.x = 0;
		origin.y = 0;
	}
	
	if ( [NSGraphicsContext currentContextDrawingToScreen] )
	{
		NSPoint offset;
		
		offset.y = offset.x = 0;
		
	//	if( QuartzExtreme)
	//	{
	//		NSRect bounds = [self bounds];
	//		[[NSColor clearColor] set];
	//		NSRectFill(bounds);
	//		
	//		NSRect ovalRect = NSMakeRect(0.0, 0.0, 50.0, 50.0);
	//		NSBezierPath *aPath = [NSBezierPath bezierPathWithOvalInRect:ovalRect];
	//		
	//		NSColor *color = [NSColor colorWithDeviceRed: 1.0 green: 0.0 blue: 0.0 alpha: 0.3];
	//		[color set];
	//		
	//		[aPath fill];
	//	}
		
		// Make this context current
		[[self openGLContext] makeCurrentContext];
//		[[self openGLContext] update];
		
		NSRect size = [self frame];
		
		glViewport (0, 0, size.size.width, size.size.height); // set the viewport to cover entire window
		
		glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
		glClear (GL_COLOR_BUFFER_BIT);
		
		if( dcmPixList && curImage > -1)
		{
			if( blendingView != 0L)
			{
				glBlendFunc(GL_ONE, GL_ONE);
				glEnable( GL_BLEND);
			}
			else glDisable( GL_BLEND);
			
			[self drawRectIn:size :pTextureName :offset :textureX :textureY];
			
			if( blendingView)
			{
				if( [curDCM pixelSpacingX] != 0 && [curDCM pixelSpacingY] != 0 &&  [[NSUserDefaults standardUserDefaults] boolForKey:@"COPYSETTINGS"] == YES)
				{
					float vectorP[ 9], tempOrigin[ 3], tempOriginBlending[ 3];
					
					[curDCM orientation: vectorP];
					
					tempOrigin[ 0] = [curDCM originX] * vectorP[ 0] + [curDCM originY] * vectorP[ 1] + [curDCM originZ] * vectorP[ 2];
					tempOrigin[ 1] = [curDCM originX] * vectorP[ 3] + [curDCM originY] * vectorP[ 4] + [curDCM originZ] * vectorP[ 5];
					tempOrigin[ 2] = [curDCM originX] * vectorP[ 6] + [curDCM originY] * vectorP[ 7] + [curDCM originZ] * vectorP[ 8];
					
					tempOriginBlending[ 0] = [[blendingView curDCM] originX] * vectorP[ 0] + [[blendingView curDCM] originY] * vectorP[ 1] + [[blendingView curDCM] originZ] * vectorP[ 2];
					tempOriginBlending[ 1] = [[blendingView curDCM] originX] * vectorP[ 3] + [[blendingView curDCM] originY] * vectorP[ 4] + [[blendingView curDCM] originZ] * vectorP[ 5];
					tempOriginBlending[ 2] = [[blendingView curDCM] originX] * vectorP[ 6] + [[blendingView curDCM] originY] * vectorP[ 7] + [[blendingView curDCM] originZ] * vectorP[ 8];
					
					offset.x = (tempOrigin[0] + [curDCM pwidth]*[curDCM pixelSpacingX]/2. - (tempOriginBlending[ 0] + [[blendingView curDCM] pwidth]*[[blendingView curDCM] pixelSpacingX]/2.));
					offset.y = (tempOrigin[1] + [curDCM pheight]*[curDCM pixelSpacingY]/2. - (tempOriginBlending[ 1] + [[blendingView curDCM] pheight]*[[blendingView curDCM] pixelSpacingY]/2.));
					
					offset.x *= scaleValue;
					offset.x /= [curDCM pixelSpacingX];
					
					offset.y *= scaleValue;
					offset.y /= [curDCM pixelSpacingY];
				}
				else
				{
					offset.y = 0;
					offset.x = 0;
				}
				
				//NSLog(@"offset:%f - %f", offset.x, offset.y);
				
				glBlendEquation(GL_FUNC_ADD);
				glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
				
				if( blendingTextureName)
					[blendingView drawRectIn:size :blendingTextureName :offset :blendingTextureX :blendingTextureY];
				else
					NSLog( @"blendingTextureName == 0L");
					
				glDisable( GL_BLEND);
			}
			
			// ***********************
			// DRAW CLUT BARS ********
			
			if( [[[self window] windowController] is2DViewer] == YES && annotations != annotNone)
			{
				if( clutBars == barOrigin || clutBars == barBoth)
				{
					float			heighthalf = size.size.height/2 - 1;
					float			widthhalf = size.size.width/2 - 1;
					long			yRaster = 1, xRaster, i;
					NSString		*tempString = 0L;
					
					#define BARPOSX1 50.f
					#define BARPOSX2 20.f
					
					heighthalf = 0;
					
					glLoadIdentity (); // reset model view matrix to identity (eliminates rotation basically)
					glScalef (2.0f /(xFlipped ? -(size.size.width) : size.size.width), -2.0f / (yFlipped ? -(size.size.height) : size.size.height), 1.0f);
					
					glLineWidth(1.0);
					glBegin(GL_LINES);
					for( i = 0; i < 256; i++)
					{
						glColor3ub ( redTable[ i], greenTable[ i], blueTable[ i]);
						
						glVertex2f(  widthhalf - BARPOSX1, heighthalf - (-128.f + i));
						glVertex2f(  widthhalf - BARPOSX2, heighthalf - (-128.f + i));
					}
					glColor3ub ( 128, 128, 128);
					glVertex2f(  widthhalf - BARPOSX1, heighthalf - -128.f);		glVertex2f(  widthhalf - BARPOSX2 , heighthalf - -128.f);
					glVertex2f(  widthhalf - BARPOSX1, heighthalf - 127.f);			glVertex2f(  widthhalf - BARPOSX2 , heighthalf - 127.f);
					glVertex2f(  widthhalf - BARPOSX1, heighthalf - -128.f);		glVertex2f(  widthhalf - BARPOSX1, heighthalf - 127.f);
					glVertex2f(  widthhalf - BARPOSX2 ,heighthalf -  -128.f);		glVertex2f(  widthhalf - BARPOSX2, heighthalf - 127.f);
					glEnd();
					
					if( curWW < 50)
					{
						tempString = [NSString stringWithFormat: @"%0.4f", curWL - curWW/2];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - -133 rightAlignment: YES useStringTexture: NO];
						
						tempString = [NSString stringWithFormat: @"%0.4f", curWL];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - 0 rightAlignment: YES useStringTexture: NO];
						
						tempString = [NSString stringWithFormat: @"%0.4f", curWL + curWW/2];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - 120 rightAlignment: YES useStringTexture: NO];
					}
					else
					{
						tempString = [NSString stringWithFormat: @"%0.0f", curWL - curWW/2];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - -133 rightAlignment: YES useStringTexture: NO];
						
						tempString = [NSString stringWithFormat: @"%0.0f", curWL];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - 0 rightAlignment: YES useStringTexture: NO];
						
						tempString = [NSString stringWithFormat: @"%0.0f", curWL + curWW/2];
						[self DrawNSStringGL: tempString : labelFontListGL :widthhalf - BARPOSX1: heighthalf - 120 rightAlignment: YES useStringTexture: NO];
					}
				} //clutBars == barOrigin || clutBars == barBoth
				
				if( blendingView)
				{
					if( clutBars == barFused || clutBars == barBoth)
					{
						unsigned char	*bred, *bgreen, *bblue;
						float			heighthalf = size.size.height/2 - 1;
						float			widthhalf = size.size.width/2 - 1;
						long			yRaster = 1, xRaster, i;
						float			bwl, bww;
						NSString		*tempString = 0L;
						
						if( [[[NSUserDefaults standardUserDefaults] stringForKey:@"PET Clut Mode"] isEqualToString: @"B/W Inverse"])
						{
							bred = PETredTable;
							bgreen = PETgreenTable;
							bblue = PETblueTable;
						}
						else [blendingView getCLUT:&bred :&bgreen :&bblue];
						
						#define BBARPOSX1 55.f
						#define BBARPOSX2 25.f
						
						heighthalf = 0;
						
						glLoadIdentity (); // reset model view matrix to identity (eliminates rotation basically)
						glScalef (2.0f /(xFlipped ? -(size.size.width) : size.size.width), -2.0f / (yFlipped ? -(size.size.height) : size.size.height), 1.0f);
						
						glLineWidth(1.0);
						glBegin(GL_LINES);
						for( i = 0; i < 256; i++)
						{
							glColor3ub ( bred[ i], bgreen[ i], bblue[ i]);
							
							glVertex2f(  -widthhalf + BBARPOSX1, heighthalf - (-128.f + i));
							glVertex2f(  -widthhalf + BBARPOSX2, heighthalf - (-128.f + i));
						}
						glColor3ub ( 128, 128, 128);
						glVertex2f(  -widthhalf + BBARPOSX1, heighthalf - -128.f);		glVertex2f(  -widthhalf + BBARPOSX2 , heighthalf - -128.f);
						glVertex2f(  -widthhalf + BBARPOSX1, heighthalf - 127.f);		glVertex2f(  -widthhalf + BBARPOSX2 , heighthalf - 127.f);
						glVertex2f(  -widthhalf + BBARPOSX1, heighthalf - -128.f);		glVertex2f(  -widthhalf + BBARPOSX1, heighthalf - 127.f);
						glVertex2f(  -widthhalf + BBARPOSX2 ,heighthalf -  -128.f);		glVertex2f(  -widthhalf + BBARPOSX2, heighthalf - 127.f);
						glEnd();
						
						[blendingView getWLWW: &bwl :&bww];
						
						if( curWW < 50)
						{
							tempString = [NSString stringWithFormat: @"%0.4f", bwl - bww/2];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - -133];
							
							tempString = [NSString stringWithFormat: @"%0.4f", bwl];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - 0];
							
							tempString = [NSString stringWithFormat: @"%0.4f", bwl + bww/2];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - 120];
						}
						else
						{
							tempString = [NSString stringWithFormat: @"%0.0f", bwl - bww/2];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - -133];
							
							tempString = [NSString stringWithFormat: @"%0.0f", bwl];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - 0];
							
							tempString = [NSString stringWithFormat: @"%0.0f", bwl + bww/2];
							[self DrawNSStringGL: tempString : labelFontListGL :-widthhalf + BBARPOSX1 + 4: heighthalf - 120];
						}
					}
				} //blendingView
			} //[[[self window] windowController] is2DViewer] == YES
			
			
			//** SLICE CUT FOR 2D MPR
			if( cross.x != -9999 && cross.y != -9999 && display2DMPRLines == YES)
			{
				glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
				glEnable(GL_BLEND);
				glEnable(GL_POINT_SMOOTH);
				glEnable(GL_LINE_SMOOTH);
				glEnable(GL_POLYGON_SMOOTH);

				if(( mprVector[ 0] != 0 || mprVector[ 1] != 0))
				{
					float tvec[ 2];
						
					tvec[ 0] = cos((angle+90)*deg2rad);
					tvec[ 1] = sin((angle+90)*deg2rad);

					glColor3f (0.0f, 0.0f, 1.0f);
					
						// Thick Slab
						if( slab > 1)
						{
							float crossx, crossy;
							float slabx, slaby;

							glLineWidth(1.0);
							glBegin(GL_LINES);
							
							crossx = cross.x-[curDCM pwidth]/2.;
							crossy = cross.y-[curDCM pheight]/2.;
							
							slabx = (slab/2.)/[curDCM pixelSpacingX]*tvec[ 0];
							slaby = (slab/2.)/[curDCM pixelSpacingY]*tvec[ 1];
							
							glVertex2f( scaleValue * (crossx - 1000*mprVector[ 0] - slabx), scaleValue*(crossy - 1000*mprVector[ 1] - slaby));
							glVertex2f( scaleValue * (crossx + 1000*mprVector[ 0] - slabx), scaleValue*(crossy + 1000*mprVector[ 1] - slaby));

							glVertex2f( scaleValue*(crossx - 1000*mprVector[ 0]), scaleValue*(crossy - 1000*mprVector[ 1]));
							glVertex2f( scaleValue*(crossx + 1000*mprVector[ 0]), scaleValue*(crossy + 1000*mprVector[ 1]));

							glVertex2f( scaleValue*(crossx - 1000*mprVector[ 0] + slabx), scaleValue*(crossy - 1000*mprVector[ 1] + slaby));
							glVertex2f( scaleValue*(crossx + 1000*mprVector[ 0] + slabx), scaleValue*(crossy + 1000*mprVector[ 1] + slaby));
						}
						else
						{
							float crossx, crossy;
							
							glLineWidth(2.0);
							glBegin(GL_LINES);

							crossx = cross.x-[curDCM pwidth]/2.;
							crossy = cross.y-[curDCM pheight]/2.;
							
							glVertex2f( scaleValue*(crossx - 1000*mprVector[ 0]), scaleValue*(crossy - 1000*mprVector[ 1]));
							glVertex2f( scaleValue*(crossx + 1000*mprVector[ 0]), scaleValue*(crossy + 1000*mprVector[ 1]));
						}
					glEnd();
					
					if( [stringID isEqualToString:@"Original"])
					{
						glColor3f (1.0f, 0.0f, 0.0f);
						glLineWidth(1.0);
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(cross.x-[curDCM pwidth]/2. - 1000*tvec[ 0]), scaleValue*(cross.y-[curDCM pheight]/2. - 1000*tvec[ 1]));
							glVertex2f( scaleValue*(cross.x-[curDCM pwidth]/2. + 1000*tvec[ 0]), scaleValue*(cross.y-[curDCM pheight]/2. + 1000*tvec[ 1]));
						glEnd();
					}
				}

				NSPoint crossB = cross;

				crossB.x -= [curDCM pwidth]/2.;
				crossB.y -= [curDCM pheight]/2.;
				
				crossB.x *=scaleValue;
				crossB.y *=scaleValue;
				
				glColor3f (1.0f, 0.0f, 0.0f);
				
		//		if( [stringID isEqualToString:@"Perpendicular"])
		//		{
		//			glLineWidth(2.0);
		//			glBegin(GL_LINES);
		//				glVertex2f( crossB.x-BS, crossB.y);
		//				glVertex2f(  crossB.x+BS, crossB.y);
		//				
		//				glVertex2f( crossB.x, crossB.y-BS);
		//				glVertex2f(  crossB.x, crossB.y+BS);
		//			glEnd();
		//		}
		//		else
				{
					glLineWidth(2.0);
//					glBegin(GL_LINE_LOOP);
//						glVertex2f( crossB.x-BS, crossB.y-BS);
//						glVertex2f( crossB.x+BS, crossB.y-BS);
//						glVertex2f( crossB.x+BS, crossB.y+BS);
//						glVertex2f( crossB.x-BS, crossB.y+BS);
//						glVertex2f( crossB.x-BS, crossB.y-BS);
//					glEnd();
					
					glBegin(GL_LINE_LOOP);
					
					long i;
					
					#define CIRCLERESOLUTION 20
					for(i = 0; i < CIRCLERESOLUTION ; i++)
					{
					  // M_PI defined in cmath.h
					  float alpha = i * 2 * M_PI /CIRCLERESOLUTION;
					  
					  glVertex2f( crossB.x + BS*cos(alpha), crossB.y + BS*sin(alpha));
					}
					glEnd();
				}
				glLineWidth(1.0);
				
				glColor3f (0.0f, 0.0f, 0.0f);
				
				glDisable(GL_LINE_SMOOTH);
				glDisable(GL_POLYGON_SMOOTH);
				glDisable(GL_POINT_SMOOTH);
				glDisable(GL_BLEND);
			}
			
			if (annotations != annotNone)
			{
				long yRaster = 1, xRaster;
				char cstr [400], *cptr;
			
				//    NSRect size = [self frame];
				
				glLoadIdentity (); // reset model view matrix to identity (eliminates rotation basically)
				glScalef (2.0f /(xFlipped ? -(size.size.width) : size.size.width), -2.0f / (yFlipped ? -(size.size.height) : size.size.height), 1.0f); // scale to port per pixel scale

				//FRAME RECT IF MORE THAN 1 WINDOW and IF THIS WINDOW IS THE FRONTMOST
				if(( numberOf2DViewer > 1 && [[[self window] windowController] is2DViewer] == YES && stringID == 0L) || [stringID isEqualToString:@"OrthogonalMPRVIEW"])
				{
					if( [[self window] isMainWindow] && isKeyView)
					{
						float heighthalf = size.size.height/2 - 1;
						float widthhalf = size.size.width/2 - 1;
						
						glColor3f (1.0f, 0.0f, 0.0f);
						glLineWidth(2.0);
						glBegin(GL_LINE_LOOP);
							glVertex2f(  -widthhalf, -heighthalf);
							glVertex2f(  -widthhalf, heighthalf);
							glVertex2f(  widthhalf, heighthalf);
							glVertex2f(  widthhalf, -heighthalf);
						glEnd();
						glLineWidth(1.0);
					}
				}  //drawLines for ImageView Frames
				
				if ((_imageColumns > 1 || _imageRows > 1) && [[[self window] windowController] is2DViewer] == YES) {
					float heighthalf = size.size.height/2 - 1;
					float widthhalf = size.size.width/2 - 1;
					
					glColor3f (0.5f, 0.5f, 0.5f);
					glLineWidth(1.0);
					glBegin(GL_LINE_LOOP);
						glVertex2f(  -widthhalf, -heighthalf);
						glVertex2f(  -widthhalf, heighthalf);
						glVertex2f(  widthhalf, heighthalf);
						glVertex2f(  widthhalf, -heighthalf);
					glEnd();
					glLineWidth(1.0);
					if (isKeyView && [[self window] isMainWindow]) {
						float heighthalf = size.size.height/2 - 1;
						float widthhalf = size.size.width/2 - 1;
						
						glColor3f (1.0f, 0.0f, 0.0f);
						glLineWidth(2.0);
						glBegin(GL_LINE_LOOP);
							glVertex2f(  -widthhalf, -heighthalf);
							glVertex2f(  -widthhalf, heighthalf);
							glVertex2f(  widthhalf, heighthalf);
							glVertex2f(  widthhalf, -heighthalf);
						glEnd();
						glLineWidth(1.0);
					}
				}
				
				glRotatef (rotation, 0.0f, 0.0f, 1.0f); // rotate matrix for image rotation
				glTranslatef( origin.x + originOffset.x, -origin.y - originOffset.y, 0.0f);
				glScalef( 1.f, [curDCM pixelRatio], 1.f);
				
				// Draw ROIs
				BOOL drawROI = NO;
				
				if( [[[self window] windowController] is2DViewer] == YES) drawROI = [[[[self window] windowController] roiLock] tryLock];
				else drawROI = YES;
				
				if( drawROI)
				{
					BOOL resetData = NO;
					if(_imageColumns > 1 || _imageRows > 1) resetData = YES;	//For alias ROIs
				
					rectArray = [[NSMutableArray alloc] initWithCapacity: [curRoiList count]];
					long i;
					for( i = 0; i < [curRoiList count]; i++)
					{
						if( resetData) [[curRoiList objectAtIndex:i] recompute];
						[[curRoiList objectAtIndex:i] setRoiFont: labelFontListGL :labelFontListGLSize :self];
						[[curRoiList objectAtIndex:i] drawROI: scaleValue :[curDCM pwidth]/2. :[curDCM pheight]/2. :[curDCM pixelSpacingX] :[curDCM pixelSpacingY]];
					}
					
					if (!suppress_labels)
					{
						for( i = 0; i < [curRoiList count]; i++)
						{
							[[curRoiList objectAtIndex:i] drawTextualData];
						}
					}
					
					[rectArray release];
					rectArray = 0L;
				}
				
				if( drawROI && [[[self window] windowController] is2DViewer] == YES) [[[[self window] windowController] roiLock] unlock];
				
				// Draw 2D point cross (used when double-click in 3D panel)
				
				[self draw2DPointMarker];
				if( blendingView) [blendingView draw2DPointMarker];
				
				// Draw any Plugin objects
				
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:	[NSNumber numberWithFloat: scaleValue], @"scaleValue",
																						[NSNumber numberWithFloat: [curDCM pwidth]/2.], @"offsetx",
																						[NSNumber numberWithFloat: [curDCM pheight]/2.], @"offsety",
																						[NSNumber numberWithFloat: [curDCM pixelSpacingX]], @"spacingX",
																						[NSNumber numberWithFloat: [curDCM pixelSpacingY]], @"spacingY",
																						0L];
				
				[[NSNotificationCenter defaultCenter] postNotificationName: @"PLUGINdrawObjects" object: self userInfo: userInfo];
				
				//**SLICE CUR FOR 3D MPR
				if( stringID)
				{
					if( [stringID isEqualToString:@"OrthogonalMPRVIEW"])
					{
						[self subDrawRect: aRect];
						[self setScaleValue: scaleValue];
					}
					
					if( [stringID isEqualToString:@"MPR3D"])
					{
						long	xx, yy;
						
						[[[self window] windowController] getPlanes:&xx :&yy];
						
						glColor3f (0.0f, 0.0f, 1.0f);
			
						glLineWidth(2.0);
						glBegin(GL_LINES);
							glVertex2f( -origin.x -size.size.width/2.		, scaleValue * (yy-[curDCM pheight]/2.));
							glVertex2f( -origin.x -size.size.width/2 + 100   , scaleValue * (yy-[curDCM pheight]/2.));
							
							if( yFlipped)
							{
								glVertex2f( scaleValue * (xx-[curDCM pwidth]/2.), (origin.y -size.size.height/2.)/[curDCM pixelRatio]);
								glVertex2f( scaleValue * (xx-[curDCM pwidth]/2.), (origin.y -size.size.height/2. + 100)/[curDCM pixelRatio]);
							}
							else
							{
								glVertex2f( scaleValue * (xx-[curDCM pwidth]/2.), (origin.y +size.size.height/2.)/[curDCM pixelRatio]);
								glVertex2f( scaleValue * (xx-[curDCM pwidth]/2.), (origin.y +size.size.height/2. - 100)/[curDCM pixelRatio]);
							}
						glEnd();
					}
				}
				
				
				//** SLICE CUT BETWEEN SERIES
				
				if( stringID == 0L)
				{
					glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
					glEnable(GL_BLEND);
					glEnable(GL_POINT_SMOOTH);
					glEnable(GL_LINE_SMOOTH);
					glEnable(GL_POLYGON_SMOOTH);

					if( sliceVector[ 0] != 0 | sliceVector[ 1] != 0  | sliceVector[ 2] != 0 )
					{
				
						glColor3f (0.0f, 0.6f, 0.0f);
						glLineWidth(2.0);
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePoint[ 0] - 1000*sliceVector[ 0]), scaleValue*(slicePoint[ 1] - 1000*sliceVector[ 1]));
							glVertex2f( scaleValue*(slicePoint[ 0] + 1000*sliceVector[ 0]), scaleValue*(slicePoint[ 1] + 1000*sliceVector[ 1]));
						glEnd();
						glLineWidth(1.0);
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePointI[ 0] - 1000*sliceVector[ 0]), scaleValue*(slicePointI[ 1] - 1000*sliceVector[ 1]));
							glVertex2f( scaleValue*(slicePointI[ 0] + 1000*sliceVector[ 0]), scaleValue*(slicePointI[ 1] + 1000*sliceVector[ 1]));
						glEnd();
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePointO[ 0] - 1000*sliceVector[ 0]), scaleValue*(slicePointO[ 1] - 1000*sliceVector[ 1]));
							glVertex2f( scaleValue*(slicePointO[ 0] + 1000*sliceVector[ 0]), scaleValue*(slicePointO[ 1] + 1000*sliceVector[ 1]));
						glEnd();
						
						if( slicePoint3D[ 0] != 0 | slicePoint3D[ 1] != 0  | slicePoint3D[ 2] != 0 )
						{
							float vectorP[ 9], tempPoint3D[ 3], rotateVector[ 2];
							
						//	glColor3f (0.6f, 0.0f, 0.0f);
							
							[curDCM orientation: vectorP];
							
							glLineWidth(2.0);
							
						//	NSLog(@"Before: %2.2f / %2.2f / %2.2f", slicePoint3D[ 0], slicePoint3D[ 1], slicePoint3D[ 2]);
							
							slicePoint3D[ 0] -= [curDCM originX];
							slicePoint3D[ 1] -= [curDCM originY];
							slicePoint3D[ 2] -= [curDCM originZ];
							
							tempPoint3D[ 0] = slicePoint3D[ 0] * vectorP[ 0] + slicePoint3D[ 1] * vectorP[ 1] + slicePoint3D[ 2] * vectorP[ 2];
							tempPoint3D[ 1] = slicePoint3D[ 0] * vectorP[ 3] + slicePoint3D[ 1] * vectorP[ 4] + slicePoint3D[ 2] * vectorP[ 5];
							tempPoint3D[ 2] = slicePoint3D[ 0] * vectorP[ 6] + slicePoint3D[ 1] * vectorP[ 7] + slicePoint3D[ 2] * vectorP[ 8];
							
							slicePoint3D[ 0] += [curDCM originX];
							slicePoint3D[ 1] += [curDCM originY];
							slicePoint3D[ 2] += [curDCM originZ];
							
						//	NSLog(@"After: %2.2f / %2.2f / %2.2f", tempPoint3D[ 0], tempPoint3D[ 1], tempPoint3D[ 2]);
							
							tempPoint3D[0] /= [curDCM pixelSpacingX];
							tempPoint3D[1] /= [curDCM pixelSpacingY];
							
							tempPoint3D[0] -= [curDCM pwidth]/2.;
							tempPoint3D[1] -= [curDCM pheight]/2.;
							
							rotateVector[ 0] = sliceVector[ 1];
							rotateVector[ 1] = -sliceVector[ 0];
							
							glBegin(GL_LINES);
								glVertex2f( scaleValue*(tempPoint3D[ 0]-20/[curDCM pixelSpacingX] *(rotateVector[ 0])), scaleValue*(tempPoint3D[ 1]-20/[curDCM pixelSpacingY]*(rotateVector[ 1])));
								glVertex2f( scaleValue*(tempPoint3D[ 0]+20/[curDCM pixelSpacingX] *(rotateVector[ 0])), scaleValue*(tempPoint3D[ 1]+20/[curDCM pixelSpacingY]*(rotateVector[ 1])));
							glEnd();
							
							glLineWidth(1.0);
						}
					}
					
					if( sliceVector2[ 0] != 0 | sliceVector2[ 1] != 0  | sliceVector2[ 2] != 0 )
					{
						glColor3f (0.0f, 0.6f, 0.0f);
						glLineWidth(2.0);
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePoint2[ 0] - 1000*sliceVector2[ 0]), scaleValue*(slicePoint2[ 1] - 1000*sliceVector2[ 1]));
							glVertex2f( scaleValue*(slicePoint2[ 0] + 1000*sliceVector2[ 0]), scaleValue*(slicePoint2[ 1] + 1000*sliceVector2[ 1]));
						glEnd();
						glLineWidth(1.0);
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePointI2[ 0] - 1000*sliceVector2[ 0]), scaleValue*(slicePointI2[ 1] - 1000*sliceVector2[ 1]));
							glVertex2f( scaleValue*(slicePointI2[ 0] + 1000*sliceVector2[ 0]), scaleValue*(slicePointI2[ 1] + 1000*sliceVector2[ 1]));
						glEnd();
						glBegin(GL_LINES);
							glVertex2f( scaleValue*(slicePointO2[ 0] - 1000*sliceVector2[ 0]), scaleValue*(slicePointO2[ 1] - 1000*sliceVector2[ 1]));
							glVertex2f( scaleValue*(slicePointO2[ 0] + 1000*sliceVector2[ 0]), scaleValue*(slicePointO2[ 1] + 1000*sliceVector2[ 1]));
						glEnd();
					}
					
					glDisable(GL_LINE_SMOOTH);
					glDisable(GL_POLYGON_SMOOTH);
					glDisable(GL_POINT_SMOOTH);
					glDisable(GL_BLEND);
				}
				
				glLoadIdentity (); // reset model view matrix to identity (eliminates rotation basically)
				glScalef (2.0f / size.size.width, -2.0f /  size.size.height, 1.0f); // scale to port per pixel scale
				
				glColor3f (0.0f, 1.0f, 0.0f);
				
				 if( annotations >= annotBase)
				 {
					//** PIXELSPACING LINES
					glBegin(GL_LINES);
					if ([curDCM pixelSpacingX] != 0 && [curDCM pixelSpacingX] * 1000.0 < 1)
					{
						glVertex2f(scaleValue  * (-0.02/[curDCM pixelSpacingX]), size.size.height/2 - 12); 
						glVertex2f(scaleValue  * (0.02/[curDCM pixelSpacingX]), size.size.height/2 - 12);

						glVertex2f(-size.size.width/2 + 10 , scaleValue  * (-0.02/[curDCM pixelSpacingY]*[curDCM pixelRatio])); 
						glVertex2f(-size.size.width/2 + 10 , scaleValue  * (0.02/[curDCM pixelSpacingY]*[curDCM pixelRatio]));

						short i, length;
						for (i = -20; i<=20; i++)
						{
							if (i % 10 == 0) length = 10;
							else  length = 5;
						
							glVertex2f(i*scaleValue *0.001/[curDCM pixelSpacingX], size.size.height/2 - 12);
							glVertex2f(i*scaleValue *0.001/[curDCM pixelSpacingX], size.size.height/2 - 12 - length);
							
							glVertex2f(-size.size.width/2 + 10 +  length,  i* scaleValue *0.001/[curDCM pixelSpacingY]*[curDCM pixelRatio]);
							glVertex2f(-size.size.width/2 + 10,  i* scaleValue * 0.001/[curDCM pixelSpacingY]*[curDCM pixelRatio]);
						}
					}
					else
					{
						glVertex2f(scaleValue  * (-50/[curDCM pixelSpacingX]), size.size.height/2 - 12); 
						glVertex2f(scaleValue  * (50/[curDCM pixelSpacingX]), size.size.height/2 - 12);
						
						glVertex2f(-size.size.width/2 + 10 , scaleValue  * (-50/[curDCM pixelSpacingY]*[curDCM pixelRatio])); 
						glVertex2f(-size.size.width/2 + 10 , scaleValue  * (50/[curDCM pixelSpacingY]*[curDCM pixelRatio]));

						short i, length;
						for (i = -5; i<=5; i++)
						{
							if (i % 5 == 0) length = 10;
							else  length = 5;
						
							glVertex2f(i*scaleValue *10/[curDCM pixelSpacingX], size.size.height/2 - 12);
							glVertex2f(i*scaleValue *10/[curDCM pixelSpacingX], size.size.height/2 - 12 - length);
							
							glVertex2f(-size.size.width/2 + 10 +  length,  i* scaleValue *10/[curDCM pixelSpacingY]*[curDCM pixelRatio]);
							glVertex2f(-size.size.width/2 + 10,  i* scaleValue * 10/[curDCM pixelSpacingY]*[curDCM pixelRatio]);
						}
					}
					glEnd();
					
					[self drawTextualData: size :annotations];
					
				} //annotations >= annotBase
				} //Annotation  != None
			}  
		
		else {  //no valid image  ie curImage = -1
			//NSLog(@"no IMage");
			glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
			glClear (GL_COLOR_BUFFER_BIT);
		}
		
	// Swap buffer to screen
		[[self openGLContext] flushBuffer];
		
//		GLenum err = glGetError();
//		if (GL_NO_ERROR != err)
//		{
//			NSString * errString = [NSString stringWithFormat:@"Error: %d.", err];
//			NSLog (@"%@\n", errString);
//		}
		
	}  //[NSGraphicsContext currentContextDrawingToScreen] 
	else  //not drawing to screen
	{
//        long		width, height;
//		NSRect		dstRect;
//		float		scale;
//		
//		NSLog(@"size: %f, %f", aRect.size.width, aRect.size.height);
//		
//		NSImage *im = [self nsimage:YES];
//		
//		[im setScalesWhenResized:YES];
//        
//		[[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationHigh];
//		
//		if( [im size].width / aRect.size.width > [im size].height / aRect.size.height)
//		{
//			scale = [im size].width / aRect.size.width;
//		}
//		else
//		{
//			scale = [im size].height / aRect.size.height;
//		}
//		
//		dstRect = NSMakeRect( 0, 0, [im size].width / scale, [im size].height / scale);
//		
//		[im drawRepresentation:[im bestRepresentationForDevice:nil] inRect:dstRect]; 
	}
}

- (NSMutableArray*) rectArray
{
	return rectArray;
}

- (void)reshape	// scrolled, moved or resized
{
	if( dcmPixList && [[self window] isVisible])
    {
		NSRect rect;

		//[super reshape];

		[[self openGLContext] makeCurrentContext];
//		[[self openGLContext] update];

	//	[self setIndex:curImage];

		rect = [self frame];//[self bounds];
		
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();

		glViewport(0, 0, (int) rect.size.width, (int) rect.size.height);
		
		//NSLog(@"View size: %d, %d", (int) rect.size.width, (int) rect.size.height);
		
		if( previousViewSize.width != 0)
		{
			// Adapted scale to new viewSize!
			
			float   maxChanged, xChanged = rect.size.width / previousViewSize.width, yChanged = rect.size.height / previousViewSize.height;
			
			if( xChanged < 1 || yChanged < 1)
			{
			//	if(  xChanged < yChanged) maxChanged = xChanged;
			//	else
				maxChanged = yChanged;
			}
			else
			{
			//	if(  xChanged > yChanged) maxChanged = xChanged;
			//	else
				maxChanged = yChanged;
			}
			
			if( maxChanged > 0.01 && maxChanged < 1000) maxChanged = maxChanged;
			else maxChanged = 0.01;
			
			[self setScaleValue: (scaleValue * maxChanged)];
			//scaleValue *= maxChanged;
			
			//if( scaleValue < 0.01) scaleValue = 0.01;
			
			origin.x *= maxChanged;
			origin.y *= maxChanged;
			
			originOffset.x *= maxChanged;
			originOffset.y *= maxChanged;
			
			if( [[[self window] windowController] is2DViewer] == YES)
			[[[self window] windowController] propagateSettings];
			
			if( [stringID isEqualToString:@"FinalView"] == YES || [stringID isEqualToString:@"OrthogonalMPRVIEW"]) [self blendingPropagate];
			if( [stringID isEqualToString:@"Original"] == YES) [self blendingPropagate];
		}
		previousViewSize = rect.size;
		//[self setNeedsDisplay:true];
    }
}

-(unsigned char*) getRawPixels:(long*) width :(long*) height :(long*) spp :(long*) bpp :(BOOL) screenCapture :(BOOL) force8bits
{
	return [self getRawPixels:width :height :spp :bpp :screenCapture :force8bits :YES];
}

-(unsigned char*) getRawPixels:(long*) width :(long*) height :(long*) spp :(long*) bpp :(BOOL) screenCapture :(BOOL) force8bits :(BOOL) removeGraphical
{
	unsigned char	*buf = 0L;
	long			i;
	
	if( screenCapture)	// Pixels displayed in current window
	{
	//	if( force8bits)
		{
			NSRect size = [self bounds];
			
			*width = size.size.width;
			*width/=4;
			*width*=4;
			*height = size.size.height;
			*spp = 3;
//			*spp = 4;
			*bpp = 8;
			
			buf = malloc( *width * *height * *spp * *bpp/8);
			if( buf)
			{
				if(removeGraphical)
				{
					NSString	*str = [[self stringID] retain];
					[self setStringID: @"export"];
					
					[self display];
					
					[self setStringID: str];
					[str release];
				}
				
				[[self openGLContext] makeCurrentContext];
				glReadPixels(0, 0, *width, *height, GL_RGB, GL_UNSIGNED_BYTE, buf);
				
//				unsigned char*	rgbabuf = malloc( *width * *height * 4 * *bpp/8);
//				
//				#if __BIG_ENDIAN__
//				glReadPixels(0, 0, *width, *height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, rgbabuf);	// <- This is faster, doesn't require conversion -> DMA transfer. We do the conversion with vImage
//				#else
//				glReadPixels(0, 0, *width, *height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8, rgbabuf);
//				#endif
//				
//				vImage_Buffer src, dst;
//				src.height = *height;
//				src.width = *width;
//				src.rowBytes = *width * 4;
//				src.data = rgbabuf;
//				
//				dst.height =  *height;
//				dst.width = *width;
//				dst.rowBytes = *width * 3;
//				dst.data = buf;
//				
//				
//				vImageConvert_ARGB8888toRGB888( &src, &dst, 0);
//				
//				free( rgbabuf);
				
				long rowBytes = *width**spp**bpp/8;
				
				unsigned char	*tempBuf = malloc( rowBytes);
				
				for( i = 0; i < *height/2; i++)
				{
					memcpy( tempBuf, buf + (*height - 1 - i)*rowBytes, rowBytes);
					memcpy( buf + (*height - 1 - i)*rowBytes, buf + i*rowBytes, rowBytes);
					memcpy( buf + i*rowBytes, tempBuf, rowBytes);
				}
				
				free( tempBuf);
			}
		}
//		else
//		{
//			// Convert data to 16 bits
//			vImage_Buffer			srcf, dst8;
//				
//			*spp = 1;
//			*bpp = 16;
//			*width = [curDCM pwidth];
//			*height = [curDCM pheight];
//		
//			srcf.height = *height;
//			srcf.width = *width;
//			srcf.rowBytes = *width * sizeof( float);
//			
//			dst8.height =  *height;
//			dst8.width = *width;
//			dst8.rowBytes = *width * sizeof( short);
//			
//			srcf.data = [curDCM fImage];
//			
//			i = *width * *height * *spp * *bpp / 8;
//			unsigned short	*srcBuf = malloc( i);
//			if( srcBuf)
//			{
//				dst8.data = srcBuf;
//				vImageConvert_FTo16U( &srcf, &dst8, -1024,  1, 0);	//By default, we use a 1024 rescale intercept !!
//			}
//			
//			NSPoint pt1 = [self frame].origin;
//			NSPoint pt2;
//			
//			pt2.x = [self frame].origin.x + [self frame].size.width;
//			pt2.y = [self frame].origin.y + [self frame].size.height;
//			
//			pt1 = [self ConvertFromView2GL:pt1];
//			pt2 = [self ConvertFromView2GL:pt2];
//			
//		//	NSLog( @"%f %f - %f %f", pt1.x, pt1.y, pt2.x, pt2.y);
//			
//			long newWidth, newHeight, originX, originY;
//			long x, y;
//			
//			newWidth = pt2.x - pt1.x;
//			newHeight = pt2.y - pt1.y;
//			
//			newWidth /= 2;
//			newHeight /= 2;
//			newWidth *= 2;
//			newHeight *= 2;
//			
//			originX = pt1.x;
//			originY = pt1.y;
//			
//			i = newWidth * newHeight * *spp * *bpp / 8;
//			unsigned short	*cropBuf = malloc( i);
//			
//			if( cropBuf)
//			{
//				memset( cropBuf, -1024, i);
//				
//				for( x = originX; x < originX+newWidth; x++)
//				{
//					for( y = originY; y < originY+newHeight; y++)
//					{
//						if( x >= 0 && x < *width && y >= 0 && y < *height)
//							cropBuf[ (x-originX) + newWidth*(y-originY)] = srcBuf[ x + *width*y];
//					}
//				}
//			}
//			
//			free( srcBuf);
//			buf = (unsigned char*) cropBuf;
//			
//			*width = newWidth;
//			*height = newHeight;
//		}
	}
	else				// Pixels contained in memory  -> only RGB or 16 bits data
	{
		BOOL	isRGB = [curDCM isRGB];
		
		*width = [curDCM pwidth];
		*height = [curDCM pheight];
		
		if( [curDCM thickSlabActivated])
		{
			force8bits = YES;
			
			if( [curDCM stackMode] == 4 || [curDCM stackMode] == 5) isRGB = YES;
		}
		
		if( isRGB == YES)
		{
			*spp = 3;
			*bpp = 8;
			
			i = *width * *height * *spp * *bpp / 8;
			buf = malloc( i);
			if( buf)
			{
				unsigned char *dst = buf, *src = (unsigned char*) [curDCM baseAddr];
				i = *width * *height;
				
				// CONVERT ARGB TO RGB
				while( i-- > 0)
				{
					src++;
					*dst++ = *src++;
					*dst++ = *src++;
					*dst++ = *src++;
				}
			}
		}
		else if( colorBuf != 0L)		// A CLUT is applied
		{
			*spp = 3;
			*bpp = 8;
			
			i = *width * *height * *spp * *bpp / 8;
			buf = malloc( i);
			if( buf)
			{
				unsigned char *dst = buf, *src = colorBuf;
				i = *width * *height;
				
				#if __BIG_ENDIAN__
				// CONVERT ARGB TO RGB
				while( i-- > 0)
				{
					src++;
					*dst++ = *src++;
					*dst++ = *src++;
					*dst++ = *src++;
				}
				#else
				while( i-- > 0)
				{
					dst[2] = src[0];
					dst[1] = src[1];
					dst[0] = src[2];
					src+=4;
					dst+=3;
				}
				#endif
			}
		}
		else
		{
			if( force8bits)	// I don't want 16 bits data, only 8 bits data
			{
				*spp = 1;
				*bpp = 8;
				
				i = *width * *height * *spp * *bpp / 8;
				buf = malloc( i);
				if( buf)
				{
					memcpy( buf, [curDCM baseAddr], *width**height);
				}
			}
			else	// Give me 16 bits !
			{
				vImage_Buffer			srcf, dst8;
				
				*spp = 1;
				*bpp = 16;
				
				srcf.height = *height;
				srcf.width = *width;
				srcf.rowBytes = *width * sizeof( float);
				
				dst8.height =  *height;
				dst8.width = *width;
				dst8.rowBytes = *width * sizeof( short);
				
				
				srcf.data = [curDCM fImage];
				
				i = *width * *height * *spp * *bpp / 8;
				buf = malloc( i);
				if( buf)
				{
					dst8.data = buf;
					vImageConvert_FTo16U( &srcf, &dst8, -1024,  1, 0);	//By default, we use a 1024 rescale intercept !!
				}
			}
		}
	}
	
	return buf;
}

-(NSImage*) nsimage:(BOOL) originalSize
{
	NSBitmapImageRep	*rep;
	long				width, height, i, spp, bpp;
	NSString			*colorSpace;
	unsigned char		*data;
	
	data = [self getRawPixels :&width :&height :&spp :&bpp :!originalSize : YES];
	
	if( spp == 3) colorSpace = NSCalibratedRGBColorSpace;
	else colorSpace = NSCalibratedWhiteColorSpace;
	
	rep = [[[NSBitmapImageRep alloc]
			 initWithBitmapDataPlanes:0L
						   pixelsWide:width
						   pixelsHigh:height
						bitsPerSample:bpp
					  samplesPerPixel:spp
							 hasAlpha:NO
							 isPlanar:NO
					   colorSpaceName:colorSpace
						  bytesPerRow:width*bpp*spp/8
						 bitsPerPixel:bpp*spp] autorelease];
	
	memcpy( [rep bitmapData], data, height*width*bpp*spp/8);
	
	NSImage *image = [[NSImage alloc] init];
	[image addRepresentation:rep];
     
	free( data);
	 
    return image;
}

-(float) scaleValue;
{
	return scaleValue;
}

-(void) setScaleValueCentered:(float) x
{
	if( scaleValue)
	{
		origin.x = ((origin.x * x) / scaleValue);
		origin.y = ((origin.y * x) / scaleValue);
				
		originOffset.x = ((originOffset.x * x) / scaleValue);
		originOffset.y = ((originOffset.y * x) / scaleValue);
	}
	scaleValue = x;
	
	if( x < 0.01) scaleValue = 0.01;
	if( x > 100) scaleValue = 100;
	
	[self setNeedsDisplay:YES];
}

-(void) setScaleValue:(float) x
{
	if( scaleValue != x)
	{
		scaleValue = x;
		if( x < 0.01) scaleValue = 0.01;
		if( x > 100) scaleValue = 100;

	//	if( scaleValue > 0.01 && scaleValue < 100) scaleValue = scaleValue;
	//	else scaleValue = 0.01;
		
		[self setNeedsDisplay:YES];
	}
}

-(NSMutableArray*) dcmPixList
{
	return dcmPixList;
}

-(NSMutableArray*) dcmRoiList
{
	return dcmRoiList;
}

- (long) indexForPix: (long) pixIndex
{
	if ([[[dcmFilesList objectAtIndex:0] valueForKey:@"numberOfFrames"] intValue] == 1)
		return curImage;
	else
		return 0;
}

- (long) syncSeriesIndex
{
	return syncSeriesIndex;
}

-(void) setSyncSeriesIndex:(long) i
{
	syncSeriesIndex = i;
}

-(void) setAlpha:(float) a
{
	long	i;
	float   val, ii;
	float   src[ 256];
	
	switch( blendingMode)
	{
		case 0:				// LINEAR FUSION
			for( i = 0; i < 256; i++) src[ i] = i;
		break;
		
		case 1:				// HIGH-LOW-HIGH
			for( i = 0; i < 128; i++) src[ i] = (127 - i)*2;
			for( i = 128; i < 256; i++) src[ i] = (i-127)*2;
		break;
		
		case 2:				// LOW-HIGH-LOW
			for( i = 0; i < 128; i++) src[ i] = i*2;
			for( i = 128; i < 256; i++) src[ i] = 256 - (i-127)*2;
		break;
		
		case 3:				// LOG
			for( i = 0; i < 256; i++) src[ i] = 255. * log10( 1. + (i/255.)*9.);
		break;
		
		case 4:				// LOG INV
			for( i = 0; i < 256; i++) src[ i] = 255. * (1. - log10( 1. + ((255-i)/255.)*9.));
		break;
		
		case 5:				// FLAT
			for( i = 0; i < 256; i++) src[ i] = 128;
		break;
	}
	
	if( a <= 0)
	{
		a += 256;
		
		for(i=0; i < 256; i++) 
		{
			ii = src[ i];
			val = (a * ii) / 256.;
			
			if( val > 255) val = 255;
			if( val < 0) val = 0;
			alphaTable[i] = val;
		}
	}
	else
	{
		if( a == 256) for(i=0; i < 256; i++) alphaTable[i] = 255;
		else
		{
			for(i=0; i < 256; i++) 
			{
				ii = src[ i];
				val = (256. * ii)/(256 - a);
				
				if( val > 255) val = 255;
				if( val < 0) val = 0;
				alphaTable[i] = val;
			}
		}
	}
}

-(void) setBlendingFactor:(float) f
{
	blendingFactor = f;
	
	[blendingView setAlpha: blendingFactor];
	[self loadTextures];
	[self setNeedsDisplay: YES];
}

-(void) setBlendingMode:(long) f
{
	blendingMode = f;
	
	[blendingView setBlendingMode: blendingMode];
	
	[blendingView setAlpha: blendingFactor];
	
	[self loadTextures];
	[self setNeedsDisplay: YES];
}

-(float) rotation;
{
	return rotation;
}

-(void) setRotation:(float) x
{
	rotation = x;
	
	if( rotation < 0) rotation += 360;
	if( rotation > 360) rotation -= 360;
	
	[[self seriesObj] setValue:[NSNumber numberWithFloat:rotation] forKey:@"rotationAngle"];
}

-(NSPoint) origin
{
	return origin;
}

-(NSPoint) originOffset
{
	return originOffset;
}

-(void) setOrigin:(NSPoint) x
{
	if( x.x > -100000 && x.x < 100000) x.x = x.x;
	else x.x = 0;

	if( x.y > -100000 && x.y < 100000) x.y = x.y;
	else x.y = 0;
	
	origin = x;
	
	[self setNeedsDisplay:YES];
}

-(void) setOriginOffset:(NSPoint) x
{
	originOffset = x;
	
	[self setNeedsDisplay:YES];
}

- (void) colorTables:(unsigned char **) a :(unsigned char **) r :(unsigned char **)g :(unsigned char **) b
{
	*a = alphaTable;
	*r = redTable;
	*g = greenTable;
	*b = blueTable;
}

- (void) blendingColorTables:(unsigned char **) a :(unsigned char **) r :(unsigned char **)g :(unsigned char **) b
{
	if( [[[NSUserDefaults standardUserDefaults] stringForKey:@"PET Clut Mode"] isEqualToString: @"B/W Inverse"])
	{
		*a = alphaTable;
		*r = PETredTable;
		*g = PETgreenTable;
		*b = PETblueTable;
	}
	else
	{
		[blendingView colorTables:a :r :g :b];
	}
}

- (GLuint *) loadTextureIn:(GLuint *) texture blending:(BOOL) blending colorBuf: (unsigned char**) colorBufPtr textureX:(long*) tX textureY:(long*) tY redTable:(unsigned char*) rT greenTable:(unsigned char*) gT blueTable:(unsigned char*) bT 
{
	if(  rT == 0L)
	{
		rT = redTable;
		gT = greenTable;
		bT = blueTable;
	}

	if( curDCM == 0L) NSLog( @"err curDCM == 0L");
	
	if( noScale == YES)
	{
		[curDCM changeWLWW :127 : 256];
	}
	
	if( mainThread != [NSThread currentThread])
	{
		NSLog(@"Warning! OpenGL activity NOT in the main thread???");
	}
	
    if( texture)
	{
		glDeleteTextures( *tX * *tY, texture);
		free( (char*) texture);
		texture = 0L;
	}
	
	if( [curDCM isRGB] == YES)
	{
		if((colorTransfer == YES) || (blending == YES))
		{
			vImage_Buffer src, dest;
			
			[curDCM changeWLWW :curWL: curWW];
			
			src.height = [curDCM pheight];
			src.width = [curDCM pwidth];
			src.rowBytes = [curDCM rowBytes];
			src.data = [curDCM baseAddr];
			
			dest.height = [curDCM pheight];
			dest.width = [curDCM pwidth];
			dest.rowBytes = [curDCM rowBytes];
			dest.data = [curDCM baseAddr];
			
			if( redFactor != 1.0 || greenFactor != 1.0 || blueFactor != 1.0)
			{
				unsigned char  credTable[256], cgreenTable[256], cblueTable[256];
				long i;
				
				for( i = 0; i < 256; i++)
				{
					credTable[ i] = rT[ i] * redFactor;
					cgreenTable[ i] = gT[ i] * greenFactor;
					cblueTable[ i] = bT[ i] * blueFactor;
				}
				#if __BIG_ENDIAN__
				vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) &alphaTable, (Pixel_8*) &credTable, (Pixel_8*) &cgreenTable, (Pixel_8*) &cblueTable, 0);
				#else
				vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) &cblueTable, (Pixel_8*) &cgreenTable, (Pixel_8*) &credTable, (Pixel_8*) &alphaTable, 0);
				#endif
			}
			else
			{
				#if __BIG_ENDIAN__
				vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) &alphaTable, (Pixel_8*) rT, (Pixel_8*) gT, (Pixel_8*) bT, 0);
				#else
				vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) bT, (Pixel_8*) gT, (Pixel_8*) rT, (Pixel_8*) &alphaTable, 0);
				#endif
			}
		}
		else if( redFactor != 1.0 || greenFactor != 1.0 || blueFactor != 1.0)
		{
			unsigned char  credTable[256], cgreenTable[256], cblueTable[256];
			long i;
			
			vImage_Buffer src, dest;
			
			[curDCM changeWLWW :curWL: curWW];
			
			src.height = [curDCM pheight];
			src.width = [curDCM pwidth];
			src.rowBytes = [curDCM rowBytes];
			src.data = [curDCM baseAddr];
			
			dest.height = [curDCM pheight];
			dest.width = [curDCM pwidth];
			dest.rowBytes = [curDCM rowBytes];
			dest.data = [curDCM baseAddr];
			
			for( i = 0; i < 256; i++)
			{
				credTable[ i] = rT[ i] * redFactor;
				cgreenTable[ i] = gT[ i] * greenFactor;
				cblueTable[ i] = bT[ i] * blueFactor;
			}
			#if __BIG_ENDIAN__
			vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) &alphaTable, (Pixel_8*) &credTable, (Pixel_8*) &cgreenTable, (Pixel_8*) &cblueTable, 0);
			#else
			vImageTableLookUp_ARGB8888( &dest, &dest, (Pixel_8*) &cblueTable, (Pixel_8*) &cgreenTable, (Pixel_8*) &credTable, (Pixel_8*) &alphaTable, 0);
			#endif

		}
	}
	else if( (colorTransfer == YES) || (blending == YES))
	{
		if( *colorBufPtr)
		{
			free( *colorBufPtr);
		}
		*colorBufPtr = malloc( [curDCM rowBytes] * [curDCM pheight] * 4);
		
		vImage_Buffer src8, dest8;
		
		src8.height = [curDCM pheight];
		src8.width = [curDCM pwidth];
		src8.rowBytes = [curDCM rowBytes];
		src8.data = [curDCM baseAddr];
		
		dest8.height = [curDCM pheight];
		dest8.width = [curDCM pwidth];
		dest8.rowBytes = [curDCM rowBytes]*4;
		dest8.data = *colorBufPtr;
		
		vImageConvert_Planar8toARGB8888(&src8, &src8, &src8, &src8, &dest8, 0);
		
		if( redFactor != 1.0 || greenFactor != 1.0 || blueFactor != 1.0)
		{
			unsigned char  credTable[256], cgreenTable[256], cblueTable[256];
			long i;
			
			for( i = 0; i < 256; i++)
			{
				credTable[ i] = rT[ i] * redFactor;
				cgreenTable[ i] = gT[ i] * greenFactor;
				cblueTable[ i] = bT[ i] * blueFactor;
			}
			vImageTableLookUp_ARGB8888( &dest8, &dest8, (Pixel_8*) &alphaTable, (Pixel_8*) &credTable, (Pixel_8*) &cgreenTable, (Pixel_8*) &cblueTable, 0);
		}
		else vImageTableLookUp_ARGB8888( &dest8, &dest8, (Pixel_8*) &alphaTable, (Pixel_8*) rT, (Pixel_8*) gT, (Pixel_8*) bT, 0);
	}
	
//	glDisable(GL_TEXTURE_2D);
    glEnable(TEXTRECTMODE);
	
	if( [curDCM isRGB] == YES || [curDCM thickSlabActivated] == YES) textureWidth = [curDCM rowBytes]/4;
    else textureWidth = [curDCM rowBytes];
	
	textureHeight = [curDCM pheight];
	
    glPixelStorei (GL_UNPACK_ROW_LENGTH, textureWidth); // set image width in groups (pixels), accounts for border this ensures proper image alignment row to row
    // get number of textures x and y
    // extract the number of horiz. textures needed to tile image
    *tX = GetTextureNumFromTextureDim (textureWidth, maxTextureSize, false, f_ext_texture_rectangle); //OVERLAP
    // extract the number of horiz. textures needed to tile image
    *tY = GetTextureNumFromTextureDim (textureHeight, maxTextureSize, false, f_ext_texture_rectangle); //OVERLAP
	
	texture = (GLuint *) malloc ((long) sizeof (GLuint) * *tX * *tY);
	
//	NSLog( @"%d %d - No Of Textures: %d", textureWidth, textureHeight, *tX * *tY);
	if( *tX * *tY > 1) NSLog(@"NoOfTextures: %d", *tX * *tY);
	glTextureRangeAPPLE(TEXTRECTMODE, textureWidth * textureHeight * 4, [curDCM baseAddr]);
	glGenTextures (*tX * *tY, texture); // generate textures names need to support tiling
    {
            long x, y, k = 0, offsetY, offsetX = 0, currWidth, currHeight; // texture iterators, texture name iterator, image offsets for tiling, current texture width and height
            for (x = 0; x < *tX; x++) // for all horizontal textures
            {
				currWidth = GetNextTextureSize (textureWidth - offsetX, maxTextureSize, f_ext_texture_rectangle); // use remaining to determine next texture size 
				
				offsetY = 0; // reset vertical offest for every column
				for (y = 0; y < *tY; y++) // for all vertical textures
				{
					unsigned char * pBuffer;
					
					if( [curDCM isRGB] == YES || [curDCM thickSlabActivated] == YES)
					{
						pBuffer =   (unsigned char*) [curDCM baseAddr] +			//baseAddr
									offsetY * [curDCM rowBytes] +      //depth
									offsetX * 4;							//depth
					}
					else if( (colorTransfer == YES) || (blending == YES))
						pBuffer =  *colorBufPtr +			//baseAddr
									offsetY * [curDCM rowBytes] * 4 +      //depth
									offsetX * 4;							//depth
									
					else pBuffer =  (unsigned char*) [curDCM baseAddr] +			
									offsetY * [curDCM rowBytes] +      
									offsetX;							
					
					currHeight = GetNextTextureSize (textureHeight - offsetY, maxTextureSize, f_ext_texture_rectangle); // use remaining to determine next texture size
					glBindTexture (TEXTRECTMODE, texture[k++]);
					
					glTexParameterf (TEXTRECTMODE, GL_TEXTURE_PRIORITY, 1.0f);
					
					if (f_ext_client_storage) glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, 1);	// Incompatible with GL_TEXTURE_STORAGE_HINT_APPLE
					else  glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, 0);
					
					if (f_arb_texture_rectangle && f_ext_texture_rectangle)
					{
						if( textureWidth > 2048 && textureHeight > 2048 || [self class] == [OrthogonalMPRPETCTView class] || [self class] == [OrthogonalMPRView class])
						{
							glTexParameteri (TEXTRECTMODE, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);		//<- this produce 'artefacts' when changing WL&WW for small matrix in RGB images... if	GL_UNPACK_CLIENT_STORAGE_APPLE is set to 1
						}
					}
						
					if( [[NSUserDefaults standardUserDefaults] boolForKey:@"NOINTERPOLATION"])
					{
						glTexParameteri (TEXTRECTMODE, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
						glTexParameteri (TEXTRECTMODE, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
					}
					else
					{
						glTexParameteri (TEXTRECTMODE, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
						glTexParameteri (TEXTRECTMODE, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
					}
					glTexParameteri (TEXTRECTMODE, GL_TEXTURE_WRAP_S, edgeClampParam);
					glTexParameteri (TEXTRECTMODE, GL_TEXTURE_WRAP_T, edgeClampParam);
					
					#if __BIG_ENDIAN__
					if( [curDCM isRGB] == YES || [curDCM thickSlabActivated] == YES) glTexImage2D (TEXTRECTMODE, 0, GL_RGBA, currWidth, currHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV, pBuffer);
					else if( (colorTransfer == YES) | (blending == YES)) glTexImage2D (TEXTRECTMODE, 0, GL_RGBA, currWidth, currHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV, pBuffer);
					else glTexImage2D (TEXTRECTMODE, 0, GL_INTENSITY8, currWidth, currHeight, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pBuffer);
					#else
					if( [curDCM isRGB] == YES || [curDCM thickSlabActivated] == YES) glTexImage2D (TEXTRECTMODE, 0, GL_RGBA, currWidth, currHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8, pBuffer);
					else if( (colorTransfer == YES) | (blending == YES)) glTexImage2D (TEXTRECTMODE, 0, GL_RGBA, currWidth, currHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV, pBuffer);
					else glTexImage2D (TEXTRECTMODE, 0, GL_INTENSITY8, currWidth, currHeight, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pBuffer);
					#endif
					
					offsetY += currHeight;// - 2 * 1; // OVERLAP, offset in for the amount of texture used, 
					//  since we are overlapping the effective texture used is 2 texels less than texture width
				}
				offsetX += currWidth;// - 2 * 1; // OVERLAP, offset in for the amount of texture used, 
				//  since we are overlapping the effective texture used is 2 texels less than texture width
            }
    }
    glDisable (TEXTRECTMODE);
	
	return texture;
}

- (void) sliderAction2DMPR:(id) sender
{
long	x = curImage;
BOOL	lowRes = NO;

	if( [[[NSApplication sharedApplication] currentEvent] type] == NSLeftMouseDragged) lowRes = YES;

    curImage = [sender intValue];
		
	[self setIndex:curImage];
	
//	[self sendSyncMessage:curImage - x];
	
	if( lowRes) [[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object:stringID userInfo:  [NSDictionary dictionaryWithObject:@"dragged" forKey:@"action"]];
	else [[NSNotificationCenter defaultCenter] postNotificationName: @"crossMove" object:stringID userInfo:  [NSDictionary dictionaryWithObject:@"slider" forKey:@"action"]];
}

- (IBAction) sliderRGBFactor:(id) sender
{
	switch( [sender tag])
	{
		case 0: redFactor = [sender floatValue];  break;
		case 1: greenFactor = [sender floatValue];  break;
		case 2: blueFactor = [sender floatValue];  break;
	}
	
	[curDCM changeWLWW :curWL: curWW];
	
	[self loadTextures];
	[self setNeedsDisplay:YES];
}

- (void) sliderAction:(id) sender
{
//NSLog(@"DCMView sliderAction");
	long	x = curImage;//x = curImage before sliderAction

	if( flippedData) curImage = [dcmPixList count] -1 -[sender intValue];
    else curImage = [sender intValue];
		
	[self setIndex:curImage];
	
	[self sendSyncMessage:curImage - x];
	
	if( [[[self window] windowController] is2DViewer] == YES)
	{
		[[[self window] windowController] propagateSettings];
		[[[self window] windowController] adjustKeyImage];
	}
			
	if( [stringID isEqualToString:@"FinalView"] == YES) [self blendingPropagate];
}

- (void) changeGLFontNotification:(NSNotification*) note
{
	[[self openGLContext] makeCurrentContext];
	
	glDeleteLists (fontListGL, 150);
	fontListGL = glGenLists (150);
	
	[fontGL release];

	fontGL = [[NSFont fontWithName: [[NSUserDefaults standardUserDefaults] stringForKey:@"FONTNAME"] size: [[NSUserDefaults standardUserDefaults] floatForKey: @"FONTSIZE"]] retain];
	if( fontGL == 0L) fontGL = [[NSFont fontWithName:@"Geneva" size:14] retain];
	
	[fontGL makeGLDisplayListFirst:' ' count:150 base: fontListGL :fontListGLSize :NO];
	stringSize = [self sizeOfString:@"B" forFont:fontGL];
	
	[stringTextureCache release];
	stringTextureCache = 0L;
	
	[self setNeedsDisplay:YES];
}

- (void)changeFont:(id)sender
{
    NSFont *oldFont = fontGL;
    NSFont *newFont = [sender convertFont:oldFont];
	
	[[NSUserDefaults standardUserDefaults] setObject: [newFont fontName] forKey: @"FONTNAME"];
	[[NSUserDefaults standardUserDefaults] setFloat: [newFont pointSize] forKey: @"FONTSIZE"];
	[NSFont resetFont: NO];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"changeGLFontNotification" object: sender];
}

- (void)loadTextures
{
    [[self openGLContext] makeCurrentContext];
	
	pTextureName = [self loadTextureIn:pTextureName blending:NO colorBuf:&colorBuf textureX:&textureX textureY:&textureY redTable: redTable greenTable:greenTable blueTable:blueTable];
	
	if( blendingView)
	{
		if( [[[NSUserDefaults standardUserDefaults] stringForKey:@"PET Clut Mode"] isEqualToString: @"B/W Inverse"])
			blendingTextureName = [blendingView loadTextureIn:blendingTextureName blending:YES colorBuf:&blendingColorBuf textureX:&blendingTextureX textureY:&blendingTextureY redTable: PETredTable greenTable:PETgreenTable blueTable:PETblueTable];
		else
			blendingTextureName = [blendingView loadTextureIn:blendingTextureName blending:YES colorBuf:&blendingColorBuf textureX:&blendingTextureX textureY:&blendingTextureY redTable:0L greenTable:0L blueTable:0L];
	}
}

- (BOOL)becomeFirstResponder{	

	[[NSNotificationCenter defaultCenter] postNotificationName: @"DCMNewImageViewResponder" object: self userInfo: 0L];
	if (curImage < 0)
		if( listType == 'i') [self setIndex:0];
	else [self setIndexWithReset:0 :YES];
	
	isKeyView = YES;
	[self setNeedsDisplay:YES];
	
	return YES;
}

//- (BOOL)resignFirstResponder{
//	isKeyView = NO;
//	return [super resignFirstResponder];
//}

//- (void)changeColor:(id)sender{
//	NSLog(@"changed color");
//	[fontColor release];
//	fontColor = [[(NSColorPanel *)sender color] retain];	
//	[self setNeedsDisplay:YES];
//	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fontColor  forKey:@"fontColor"];
//	[[NSNotificationCenter defaultCenter] postNotificationName: @"DCMNewFontColor" object: self userInfo: 0L];
//}
//
//-(void)setFontColor:(NSNotification *)note{
//	if ([note object] != self) {
//		[fontColor release];
//		fontColor = [[note userInfo] objectForKey:@"fontColor"];	
//		[self setNeedsDisplay:YES];
//	}
//}
	
// ** TILING SUPPORT

- (id)initWithFrame:(NSRect)frame {

	[AppController initialize];

	return [self initWithFrame:frame imageRows:1  imageColumns:1];

}

- (id)initWithFrame:(NSRect)frame imageRows:(int)rows  imageColumns:(int)columns{
	self = [self initWithFrameInt:frame];
    if (self) {
        _tag = 0;
		_imageRows = rows;
		_imageColumns = columns;
		isKeyView = NO;
		[self setAutoresizingMask:NSViewMinXMargin];
		
		noScale = NO;
		flippedData = NO;
		
		//notifications
		NSNotificationCenter *nc;
		nc = [NSNotificationCenter defaultCenter];
		[nc addObserver: self
           selector: @selector(updateCurrentImage:)
               name: @"DCMUpdateCurrentImage"
             object: nil];
		[nc addObserver: self
           selector: @selector(updateImageTiling:)
               name: @"DCMImageTilingHasChanged"
             object: nil];
			 /*
		[nc addObserver: self
           selector: @selector(newImageViewisKey:)
               name: @"DCMNewImageViewResponder"
             object: nil];
			 */
    }
    return self;

}

-(BOOL) flippedData
{
	return flippedData;
}

-(void) setFlippedData:(BOOL) f
{
	flippedData = f;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldBoundsSiz
{
	if( [[[self window] windowController] is2DViewer] != YES)
	{
		[super resizeWithOldSuperviewSize:oldBoundsSiz];
		return;
	}
	//NSLog(@"resizeWithOldSuperviewSize:");
	NSRect superFrame = [[self superview] bounds];
	float newWidth = superFrame.size.width / _imageColumns;
	float newHeight = superFrame.size.height / _imageRows;
	float newY = newHeight * (int)(_tag / _imageColumns);
	float newX = newWidth * (int)(_tag % _imageColumns);
	NSRect newFrame = NSMakeRect(newX, newY, newWidth, newHeight);
	//NSLog(@"newFrame:x:%f y:%f  width:%f  height:%f", newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height);
	[self setFrame:newFrame];
	[self reshape];
	//[self resetCursorRects];
	[self setNeedsDisplay:YES];
}

-(void)keyUp:(NSEvent *)theEvent
{
	[super keyUp:theEvent];
	NSNotificationCenter *nc;
    nc = [NSNotificationCenter defaultCenter];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:curImage]  forKey:@"curImage"];
	[nc postNotificationName: @"DCMUpdateCurrentImage" object: self userInfo: userInfo];
}

-(void) setRows:(int)rows columns:(int)columns
{
	if( _imageRows == 1 && _imageColumns == 1 && rows == 1 && columns == 1)
	{
		NSLog(@"No Resize");
		return;
	}
	_imageRows = rows;
	_imageColumns = columns;
	NSRect rect = [[self superview] bounds];
	[self resizeWithOldSuperviewSize:rect.size];
	[self setNeedsDisplay:YES];
}

-(void)setTag:(long)aTag{
	_tag = aTag;
}
- (long)tag{
	return _tag;
}
-(float)curWW{
	return curWW;
}
-(float)curWL{
	return curWL;
}

- (int)rows{
	return _imageRows;
}
- (int)columns{
	return _imageColumns;
}

-(DCMView *)blendingView{
	return blendingView;
}

- (float)blendingMode{
	return blendingMode;
}

- (float)blendingFactor{
	return blendingFactor;
}

-(void)setImageParamatersFromView:(DCMView *)aView{
	if (aView != self)
	{
		int offset = [self tag] - [aView tag];
		curImage = [aView curImage] + offset;
		//get Image
		if (curImage >= [dcmPixList count])
			curImage = -1;
		else if (curImage < 0)
			curImage = -1;
		//set ww/wl
			curWW = [aView curWW];
			curWL = [aView curWL];
		//scale
			[self setScaleValue: [aView scaleValue]];
			//scaleValue = [aView scaleValue];
		//rotation
			rotation = [aView rotation];
			[self setXFlipped: [aView xFlipped]];
			[self setYFlipped: [aView yFlipped]];
		//translate
			origin = [aView origin];
		
		if( curImage < 0) return;
		
		//blending
		if (blendingView != [aView blendingView])
			[self setBlending:[aView blendingView]];
		if (blendingFactor != [aView blendingFactor])
			[self setBlendingFactor:[aView blendingFactor]];
		if (blendingMode != [aView blendingMode])
			[self setBlendingMode:[aView blendingMode]];
		//[self setIndex:curImage];
		if( listType == 'i') [self setIndex:curImage];
		else [self setIndexWithReset:curImage :YES];
		
		
		
		// CLUT
		unsigned char *aR, *aG, *aB;
		[aView getCLUT: &aR :&aG :&aB];
		[self setCLUT:aR :aG: aB];
		
		[self setIndex:[self curImage]];
		
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)resignFirstResponder{
	isKeyView = NO;
	[self setNeedsDisplay:YES];
	return [super resignFirstResponder];
}


//notifications

-(void) updateCurrentImage: (NSNotification*) note{

	if( stringID == 0L)
	{
		DCMView *object = [note object];
		if ([[[note object] superview] isEqual:[self superview]] && ![object isEqual: self]) 
			[self setImageParamatersFromView:object];
	}
}

-(void)updateImageTiling:(NSNotification *)note{
	if ([[self window] isKeyWindow]) 
		[self setRows:[[[note userInfo] objectForKey:@"Rows"] intValue] columns:[[[note userInfo] objectForKey:@"Columns"] intValue]];
}

-(void)newImageViewisKey:(NSNotification *)note{
	if ([note object] != self)
		isKeyView = NO;
}
//cursor methods

- (void) resetCursorRects
{
	[self addCursorRect:[self bounds] cursor: cursor];
}

- (NSCursor *)cursor{
    return cursor;
}

-(void) setCursorForView: (long) tool
{
	NSCursor	*c;
	
	if ([self roiTool:tool])
		c = [NSCursor crosshairCursor];
	else if (tool == tTranslate)
		c = [NSCursor openHandCursor];
	else if (tool == tRotate)
		c = [NSCursor rotateCursor];
	else if (tool == tZoom)
		c = [NSCursor zoomCursor];
	else if (tool == tWL)
		c = [NSCursor contrastCursor];
	else if (tool == tNext)
		c = [NSCursor stackCursor];
	else if (tool == tText)
		c = [NSCursor IBeamCursor];
	else if (tool == t3DRotate)
		c = [NSCursor crosshairCursor];
	else if (tool == tCross)
		c = [NSCursor crosshairCursor];
	else	
		c = [NSCursor arrowCursor];
		
	if( c != cursor)
	{
		[cursor release];
		
		cursor = [c retain];
		
		[[self window] invalidateCursorRectsForView: self];
	}
}

/*
*  Formula K(SUV)=K(Bq/cc)*(Wt(kg)/Dose(Bq)*1000 cc/kg 
*						  
*  Where: K(Bq/cc) = is a pixel value calibrated to Bq/cc and decay corrected to scan start time
*		 Dose = the injected dose in Bq at injection time (This value is decay corrected to scan start time. The injection time must be part of the dataset.)
*		 Wt = patient weight in kg
*		 1000=the number of cc/kg for water (an approximate conversion of patient weight to distribution volume)
*/

- (float) getBlendedSUV
{
	if( [[blendingView curDCM] SUVConverted]) return blendingPixelMouseValue;
	
	if( [[[blendingView curDCM] units] isEqualToString:@"CNTS"]) return blendingPixelMouseValue * [[blendingView curDCM] philipsFactor];
	return blendingPixelMouseValue * [[blendingView curDCM] patientsWeight] * 1000. / [[blendingView curDCM] radionuclideTotalDoseCorrected];
}

- (float)getSUV
{
	if( [curDCM SUVConverted]) return pixelMouseValue;
	
	if( [[curDCM units] isEqualToString:@"CNTS"]) return pixelMouseValue * [curDCM philipsFactor];
	else return pixelMouseValue * [curDCM patientsWeight] * 1000. / [curDCM radionuclideTotalDoseCorrected];
}

- (float)mouseXPos {
	return mouseXPos;
}

- (float)mouseYPos {
	return mouseYPos;
}

+ (void)setPluginOverridesMouse: (BOOL)override {
	pluginOverridesMouse = override;
}

- (GLuint)fontListGL {
	return fontListGL;
}

- (IBOutlet)actualSize:(id)sender{
	origin.x = origin.y = 0;
	rotation = 0;
	[self setScaleValue:1];
	//scaleValue = 1;
}
- (BOOL)eraserFlag
{
	return eraserFlag;
}
- (void)setEraserFlag: (BOOL)aFlag
{
	eraserFlag = aFlag;
}

- (NSFont*)fontGL {
	return fontGL;
}

//Database links
- (NSManagedObject *)imageObj
{
	if( stringID == 0L)
	{
		if( curDCM)	return [curDCM imageObj];
		else return 0L;
	}
	else return 0L;
}

- (NSManagedObject *)seriesObj
{
	if( stringID == 0L || [stringID isEqualToString:@"previewDatabase"])
	{
		if( curDCM) return [curDCM seriesObj];
		else return 0L;
	}
	else return 0L;
}

- (void)updatePresentationStateFromSeries{
	//get Presentation State info from series Object
	id series = [self seriesObj];
	if( series)
	{
		//NSLog(@"Series for DCMView: %@", [series valueForKey:@"seriesInstanceUID"]);
		[self setXFlipped: [[series valueForKey:@"xFlipped"] boolValue]];
		[self setYFlipped: [[series valueForKey:@"yFlipped"] boolValue]];
				
		if ([series valueForKey:@"scale"] != 0L && [[[self window] windowController] is2DViewer] == YES)
			if( [[[self seriesObj] valueForKey:@"scale"] floatValue] > 0.0)
				scaleValue = [[series valueForKey:@"scale"] floatValue];
		
		if( [series valueForKey:@"rotationAngle"])
			rotation = [[series valueForKey:@"rotationAngle"] floatValue];
		
		if ([[[self window] windowController] is2DViewer] == YES)
		{
			if( [series valueForKey:@"xOffset"]) origin.x = [[series valueForKey:@"xOffset"] floatValue];
			if( [series valueForKey:@"yOffset"]) origin.y = [[series valueForKey:@"yOffset"] floatValue];
		}
		
		if ([[self seriesObj] valueForKey:@"windowWidth"])
		{
			if( [[[self seriesObj] valueForKey:@"windowWidth"] floatValue] != 0.0)
			{
				if( [curDCM SUVConverted] == NO)
				{
					curWW = [[[self seriesObj] valueForKey:@"windowWidth"] floatValue];
					curWL = [[[self seriesObj] valueForKey:@"windowLevel"] floatValue];
				}
				else
				{
					if( [[[self window] windowController] is2DViewer] == YES)
					{
						curWW = [[[self seriesObj] valueForKey:@"windowWidth"] floatValue] * [[[self window] windowController] factorPET2SUV];
						curWL = [[[self seriesObj] valueForKey:@"windowLevel"] floatValue] * [[[self window] windowController] factorPET2SUV];
					}
				}
			}
		}
	}
}

- (IBAction)resetSeriesPresentationState:(id)sender{
	id series = [self seriesObj];
	if( series)
	{
		[self setXFlipped: NO];
		[self setYFlipped: NO];

		rotation =  0.0;
		[series setValue:[NSNumber numberWithFloat:0.0] forKey:@"rotationAngle"];
		origin.x = 0.0;
		[series setValue:[NSNumber numberWithFloat:0.0] forKey:@"xOffset"];
		origin.y = 0.0;
		[series setValue:[NSNumber numberWithFloat:0.0] forKey:@"yOffset"];
		
		[self setWLWW:[[self curDCM] savedWL] :[[self curDCM] savedWW]];
		if( [curDCM SUVConverted] == NO)
		{
			
			[series setValue:[NSNumber numberWithFloat:curWW] forKey:@"windowWidth"];
			[series setValue:[NSNumber numberWithFloat:curWL] forKey:@"windowLevel"];
		}
		else
		{
			if( [[[self window] windowController] is2DViewer] == YES)
			{
				[series setValue:[NSNumber numberWithFloat:curWW / [[[self window] windowController] factorPET2SUV]] forKey:@"windowWidth"];
				[series setValue:[NSNumber numberWithFloat:curWL / [[[self window] windowController] factorPET2SUV]] forKey:@"windowLevel"];
			}
		}
		
		[[self seriesObj] setValue:[NSNumber numberWithFloat:0] forKey:@"displayStyle"]; 
		[self scaleToFit];
	}
	[self setNeedsDisplay:YES];
		
		
}
- (IBAction)resetImagePresentationState:(id)sender{
}

//resize Window to a scale of Image Size
-(void)resizeWindowToScale:(float)resizeScale
{
	NSRect frame =  [self frame]; 
	long i;
	float curImageWidth = [curDCM pwidth] * resizeScale;
	float curImageHeight = [curDCM pheight]* resizeScale;
	float frameWidth = frame.size.width;
	float frameHeight = frame.size.height;
	NSWindow *window = [self window];
	NSRect windowFrame = [window frame];
	float newWidth = windowFrame.size.width - (frameWidth - curImageWidth) * _imageColumns;
	float newHeight = windowFrame.size.height - (frameHeight - curImageHeight) * _imageRows;
	float topLeftY = windowFrame.size.height + windowFrame.origin.y;
	NSPoint center;
	center.x = windowFrame.origin.x + windowFrame.size.width/2.0;
	center.y = windowFrame.origin.y + windowFrame.size.height/2.0;
	
	NSArray *screens = [NSScreen screens];
	
	for( i = 0; i < [screens count]; i++)
	{
		if( NSPointInRect( center, [[screens objectAtIndex: i] frame]))
		{
			NSRect	screenFrame = [[screens objectAtIndex: i] visibleFrame];
			
			if( USETOOLBARPANEL || [[NSUserDefaults standardUserDefaults] boolForKey: @"USEALWAYSTOOLBARPANEL"] == YES)
			{
				screenFrame.size.height -= [ToolbarPanelController fixedHeight];
			}
			
			if( newHeight > screenFrame.size.height) newHeight = screenFrame.size.height;
			if( newWidth > screenFrame.size.width) newWidth = screenFrame.size.width;
			
			if( center.y + newHeight/2.0 > screenFrame.size.height)
			{
				center.y = screenFrame.size.height/2.0;
			}
		}
	}
	
	windowFrame.size.height = newHeight;
	windowFrame.size.width = newWidth;

	//keep window centered
	windowFrame.origin.y = center.y - newHeight/2.0;
	windowFrame.origin.x = center.x - newWidth/2.0;
	[[self seriesObj] setValue:[NSNumber numberWithFloat:0] forKey:@"displayStyle"]; 
	
	[window setFrame:windowFrame display:YES];
	[self setScaleValue: resizeScale];
	[self setNeedsDisplay:YES];
}

- (IBAction)resizeWindow:(id)sender{
	// 2006-02-09 masu: resizing a view, which is in fullscreen mode, cuts connection
	// between view and window. When more viewers are open the app will crash.
	// So resizing is only allowed in non fullscreen mode.
	if([[[self window] windowController] FullScreenON] == FALSE)
	{
		float resizeScale = 1.0;
		float curImageWidth = [curDCM pwidth];
		float curImageHeight = [curDCM pheight];
		float widthRatio =  320.0 / curImageWidth ;
		float heightRatio =  320.0 / curImageHeight;
		switch ([sender tag]) {
			case 0: resizeScale = 0.25; // 25%
					break;
			case 1: resizeScale = 0.5;  //50%
					break;
			case 2: resizeScale = 1.0; //Actual Size 100%
					break;
			case 3: resizeScale = 2.0; // 200%
					break;
			case 4: resizeScale = 3.0; //300%
					break;
			case 5: // iPod Video
					resizeScale = (widthRatio <= heightRatio) ? widthRatio : heightRatio;
					break;
		}
		[self resizeWindowToScale:resizeScale];
	}
}

- (void)subDrawRect: (NSRect)aRect {  // Subclassable, default does nothing.
	return;
}

+ (BOOL) display2DMPRLines
{
	return display2DMPRLines;
}


#pragma mark-  PET  Tables
+ (unsigned char*) PETredTable
{
	return PETredTable;
}

+ (unsigned char*) PETgreenTable
{
	return PETgreenTable;
}

+ (unsigned char*) PETblueTable
{
	return PETblueTable;
}

#pragma mark-  Drag and Drop

- (void) startDrag:(NSTimer*)theTimer{
	NS_DURING
	_dragInProgress = YES;
	[_mouseDownTimer release];
	_mouseDownTimer = nil;
	NSEvent *event = (NSEvent *)[theTimer userInfo];
	NSSize dragOffset = NSMakeSize(0.0, 0.0);
    NSPasteboard *pboard = [NSPasteboard pasteboardWithName: NSDragPboard]; 
	NSMutableArray *pbTypes = [NSMutableArray array];
	// The image we will drag 
	NSImage *image;
	if ([event modifierFlags] & NSShiftKeyMask)
		image = [self nsimage: YES];
	else
		image = [self nsimage: NO];
		
	// Thumbnail image and position
	NSPoint event_location = [event locationInWindow];
	NSPoint local_point = [self convertPoint:event_location fromView:nil];
	local_point.x -= 35;
	local_point.y -= 35;

	NSSize originalSize = [image size];
	
	float ratio = originalSize.width / originalSize.height;
	
	NSImage *thumbnail = [[[NSImage alloc] initWithSize: NSMakeSize(100, 100/ratio)] autorelease];

	[thumbnail lockFocus];
	[image drawInRect: NSMakeRect(0, 0, 100, 100/ratio) fromRect: NSMakeRect(0, 0, originalSize.width, originalSize.height) operation: NSCompositeSourceOver fraction: 1.0];
	[thumbnail unlockFocus];
	
	if ([event modifierFlags] & NSAlternateKeyMask)
		[ pbTypes addObject: NSFilesPromisePboardType];
	else
		[pbTypes addObject: NSTIFFPboardType];	
	
	if ([self dicomImage]) {
		[pbTypes addObject:pasteBoardOsiriX];
		[pboard declareTypes:pbTypes  owner:self];
		[pboard setData:nil forType:pasteBoardOsiriX]; 
	}
	else
		[pboard declareTypes:pbTypes  owner:self];

		
	if ([event modifierFlags] & NSAlternateKeyMask) {
		NSRect imageLocation;
		local_point = [self convertPoint:event_location fromView:nil];
		imageLocation.origin =  local_point;
		imageLocation.size = NSMakeSize(32,32);
		[pboard setData:nil forType:NSFilesPromisePboardType]; 
		
		if (destinationImage)
			[destinationImage release];
		destinationImage = [image copy];
		
		[self dragPromisedFilesOfTypes:[NSArray arrayWithObject:@"jpg"]
            fromRect:imageLocation
            source:self
            slideBack:YES
            event:event];
	} 
	else {		
		[pboard setData:[image TIFFRepresentation] forType:NSTIFFPboardType];
		[ self dragImage:thumbnail
			at:local_point
			offset:dragOffset
			event:event 
			pasteboard:pboard 
			source:self 
			slideBack:YES];
	}
	
	[image release];
	
	NS_HANDLER
		NSLog(@"Exception while dragging: %@", [localException description]);
	NS_ENDHANDLER
	
	_dragInProgress = NO;
}

- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination{
	NSString *name = [[self dicomImage] valueForKeyPath:@"series.study.name"];
	name = @"OsiriX";
	name = [name stringByAppendingPathExtension:@"jpg"];
	NSArray *array = [NSArray arrayWithObject:name];
	NSData *data = [(NSBitmapImageRep *)[destinationImage bestRepresentationForDevice:nil] representationUsingType:NSJPEGFileType 
		properties:[NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.9] forKey:NSImageCompressionFactor]];
	NSURL *url = [NSURL  URLWithString:name  relativeToURL:dropDestination];
	[data writeToURL:url  atomically:YES];
	[destinationImage release];
	destinationImage = nil;
	return array;
}

- (void)deleteMouseDownTimer{
	[_mouseDownTimer invalidate];
	[_mouseDownTimer release];
	_mouseDownTimer = nil;
	_dragInProgress = NO;
}

//part of Dragging Source Protocol
- (unsigned int)draggingSourceOperationMaskForLocal:(BOOL)isLocal{
	return NSDragOperationEvery;
}

- (id)dicomImage{
	return [dcmFilesList objectAtIndex:[self indexForPix:curImage]];
}
@end