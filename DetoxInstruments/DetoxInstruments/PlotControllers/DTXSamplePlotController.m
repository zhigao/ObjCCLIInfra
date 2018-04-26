//
//  DTXSamplePlotController.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 01/06/2017.
//  Copyright © 2017 Wix. All rights reserved.
//

#import "DTXSamplePlotController.h"
#import <CorePlot/CorePlot.h>
#import "DTXGraphHostingView.h"
#import "DTXInstrumentsModel.h"
#import "NSFormatter+PlotFormatters.h"
#import "DTXLineLayer.h"
#import <LNInterpolation/LNInterpolation.h>
#import "DTXRecording+UIExtensions.h"
#import "DTXStackedPlotGroup.h"
#import "DTXCPTScatterPlot.h"
#import "DTXDetailController.h"

@interface DTXSamplePlotController () <CPTScatterPlotDelegate>

@end

@implementation DTXSamplePlotController
{
	CPTPlotRange* _globalYRange;
	CPTPlotRange* _pendingGlobalXPlotRange;
	CPTPlotRange* _pendingXPlotRange;
	
	NSStoryboard* _scene;
	
	CGRect _lastDrawBounds;
	
	CPTPlotSpaceAnnotation* _highlightAnnotation;
	DTXLineLayer* _lineLayer;
	NSUInteger _highlightedSampleIndex;
	NSUInteger _highlightedNextSampleIndex;
	NSTimeInterval _highlightedSampleTime;
	CGFloat _highlightedPercent;
	
	CPTLimitBand* _rangeHighlightBand;
	CPTPlotRange* _highlightedRange;
	
	CPTPlotSpaceAnnotation* _shadowHighlightAnnotation;
	DTXLineLayer* _shadowLineLayer;
	NSTimeInterval _shadowHighlightedSampleTime;
	
	NSArray* _plots;
	
	double _samplingInterval;
}

@synthesize delegate = _delegate;
@synthesize document = _document;
@synthesize dataProviderControllers = _dataProviderControllers;
@synthesize sampleClickDelegate = _sampleClickDelegate;

+ (Class)graphHostingViewClass
{
	return [DTXGraphHostingView class];
}

+ (Class)UIDataProviderClass
{
	return nil;
}

- (instancetype)initWithDocument:(DTXDocument*)document
{
	self = [super init];

	if(self)
	{
		_document = document;
		_scene = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
		
		_samplingInterval = [_document.recording.profilingConfiguration[@"samplingInterval"] doubleValue];
		
		//To initialize the highlighed cache ivars.
		[self removeHighlight];
	}
	
	return self;
}

- (NSArray<DTXDetailController *> *)dataProviderControllers
{
	DTXDetailController* detailController = [_scene instantiateControllerWithIdentifier:@"DTXOutlineDetailController"];
	detailController.detailDataProvider = [[self.class.UIDataProviderClass alloc] initWithDocument:_document plotController:self];
	
	return @[detailController];
}

- (void)mouseEntered:(NSEvent *)event
{
	
}

- (void)mouseExited:(NSEvent *)event
{
	[self.hostingView removeAllToolTips];
}

- (void)mouseMoved:(NSEvent *)event
{
	CGPoint pointInView = [self.hostingView convertPoint:[event locationInWindow] fromView:nil];
	
	NSMutableArray<NSDictionary<NSString*, NSString*>*>* dataPoints = [NSMutableArray new];
	
	[self.graph.allPlots enumerateObjectsUsingBlock:^(__kindof CPTPlot * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		NSUInteger numberOfRecords = [self numberOfRecordsForPlot:obj];
		NSUInteger foundPointIndex = NSNotFound;
		CGFloat foundPointDelta = 0;
		CGFloat foundPointX = 0;
		for(NSUInteger idx = 0; idx < numberOfRecords; idx++)
		{
			CGPoint pointOfPoint = [obj plotAreaPointOfVisiblePointAtIndex:idx];
			if(pointOfPoint.x <= pointInView.x)
			{
				foundPointIndex = idx;
				foundPointDelta = pointInView.x - pointOfPoint.x;
				foundPointX = pointOfPoint.x;
			}
			else
			{
				break;
			}
		}
		
		if(foundPointIndex != NSNotFound)
		{
			id y = [self numberForPlot:obj field:CPTScatterPlotFieldY recordIndex:foundPointIndex];
			if(self.isStepped == NO && foundPointIndex < numberOfRecords - 1)
			{
				CGPoint pointOfNextPoint = [obj plotAreaPointOfVisiblePointAtIndex:foundPointIndex + 1];
				id nextY = [self numberForPlot:obj field:CPTScatterPlotFieldY recordIndex:foundPointIndex + 1];
				
				y = [y interpolateToValue:nextY progress:foundPointDelta / (pointOfNextPoint.x - foundPointX)];
			}
			
			[dataPoints addObject:@{@"title":self.plotTitles[idx], @"data": [self.class.formatterForDataPresentation stringForObjectValue:[self transformedValueForFormatter:y]]}];
		}
	}];
	
	if(dataPoints.count == 0)
	{
		return;
	}
	
	[self.hostingView removeAllToolTips];
	if(dataPoints.count == 1)
	{
		[self.hostingView setToolTip:dataPoints.firstObject[@"data"]];
	}
	else
	{
		NSMutableString* tooltip = [NSMutableString new];
		[dataPoints enumerateObjectsUsingBlock:^(NSDictionary<NSString *,NSString *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			[tooltip appendString:[NSString stringWithFormat:@"%@: %@\n", obj[@"title"], obj[@"data"]]];
		}];
		
		[self.hostingView setToolTip:[tooltip stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
	}
}

- (void)_clicked:(NSClickGestureRecognizer*)cgr
{
	if(self.canReceiveFocus == NO)
	{
		return;
	}
	
	[self.delegate plotControllerUserDidClickInPlotBounds:self];
	
	if([self.graph.allPlots.firstObject isKindOfClass:[CPTScatterPlot class]])
	{
		NSPoint pointInView = [cgr locationInView:self.hostingView];
		
		CPTNumberArray* pointInPlot = [self.graph.defaultPlotSpace plotPointForPlotAreaViewPoint:pointInView];
		
		NSUInteger numberOfRecords = [self numberOfRecordsForPlot:self.plots.firstObject];
		NSUInteger foundPointIndex = NSNotFound;
		CGFloat foundPointDelta = 0;
		for(NSUInteger idx = 0; idx < numberOfRecords; idx++)
		{
			NSNumber* xOfPointInPlot = [self numberForPlot:self.graph.allPlots.firstObject field:CPTScatterPlotFieldX recordIndex:idx];
			if(xOfPointInPlot.doubleValue <= pointInPlot.firstObject.doubleValue)
			{
				foundPointIndex = idx;
				foundPointDelta = pointInPlot.firstObject.doubleValue - xOfPointInPlot.doubleValue;
			}
			else
			{
				break;
			}
		}
		
		if(foundPointIndex == NSNotFound)
		{
			return;
		}
		
		id sample = [self samplesForPlotIndex:((NSNumber*)self.plots.firstObject.identifier).unsignedIntegerValue][foundPointIndex];
		id nextSample = foundPointIndex == numberOfRecords - 1 ? nil : [self samplesForPlotIndex:((NSNumber*)self.plots.firstObject.identifier).unsignedIntegerValue][foundPointIndex + 1];
		
		[self _highlightSample:sample nextSample:nextSample plotSpaceOffset:foundPointDelta notifyDelegate:YES];
		
		[self.sampleClickDelegate plotController:self didClickOnSample:sample];
	}
}

- (void)setUpWithView:(NSView *)view
{
	[self setUpWithView:view insets:NSEdgeInsetsZero];
}

- (CPTPlotRange*)finesedPlotRangeForPlotRange:(CPTPlotRange*)_yRange;
{
	NSEdgeInsets insets = self.rangeInsets;
	
	CPTMutablePlotRange* yRange = [_yRange mutableCopy];
	
	CGFloat initial = yRange.location.doubleValue;
	yRange.location = @(-insets.bottom);
	yRange.length = @((initial + yRange.length.doubleValue + insets.top + insets.bottom) * self.yRangeMultiplier * self.sampleKeys.count);
	
	return yRange;
}

- (void)setupPlotsForGraph
{
	[self prepareSamples];
	
	NSClickGestureRecognizer* clickGestureRecognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(_clicked:)];
	[self.hostingView addGestureRecognizer:clickGestureRecognizer];
	
	NSTrackingArea* tracker = [[NSTrackingArea alloc] initWithRect:self.hostingView.bounds options:NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved owner:self userInfo:nil];
	[self.hostingView addTrackingArea:tracker];
	
	self.graph.plotAreaFrame.plotGroup = [DTXStackedPlotGroup new];
	
	self.graph.axisSet = nil;
	
	// Setup scatter plot space
	CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
	plotSpace.allowsUserInteraction = YES;
	plotSpace.delegate = self;
	
	[self.plots enumerateObjectsUsingBlock:^(CPTPlot * _Nonnull plot, NSUInteger idx, BOOL * _Nonnull stop) {
		plot.delegate = self;
		[self.graph addPlot:plot];
	}];
	
	_lastDrawBounds = self.hostingView.bounds;
	
	[[self graphAnnotationsForGraph:self.graph] enumerateObjectsUsingBlock:^(CPTPlotSpaceAnnotation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[self.graph addAnnotation:obj];
	}];
	
	// Auto scale the plot space to fit the plot data
	[plotSpace scaleToFitPlots:[self.graph allPlots]];
	
	CPTPlotRange *xRange;
	if(_pendingGlobalXPlotRange)
	{
		xRange = _pendingGlobalXPlotRange;
		_pendingGlobalXPlotRange = nil;
	}
	else
	{
		xRange = [CPTPlotRange plotRangeWithLocation:@0 length:@([_document.recording.defactoEndTimestamp timeIntervalSinceReferenceDate] - [_document.recording.defactoStartTimestamp timeIntervalSinceReferenceDate])];
	}
	CPTPlotRange *yRange = [plotSpace.yRange mutableCopy];
	
	yRange = [self finesedPlotRangeForPlotRange:yRange];
	
	plotSpace.globalXRange = xRange;
	plotSpace.globalYRange = yRange;
	_globalYRange = yRange;
	
	plotSpace.xRange = xRange;
	plotSpace.yRange = yRange;
	
	if(_pendingXPlotRange)
	{
		plotSpace.xRange = _pendingXPlotRange;
		_pendingXPlotRange = nil;
	}
}

- (NSArray<__kindof CPTPlot *> *)plots
{
	if(_plots)
	{
		return _plots;
	}
	
	NSArray<NSColor*>* plotColors = self.plotColors;
	
	NSMutableArray* rv = [NSMutableArray new];
	[self.sampleKeys enumerateObjectsUsingBlock:^(NSString* _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		// Create the plot
		CPTScatterPlot* scatterPlot = [[DTXCPTScatterPlot alloc] initWithFrame:CGRectZero];
		scatterPlot.identifier = @(idx);
		
		// set interpolation types
		scatterPlot.interpolation = self.isStepped ? CPTScatterPlotInterpolationStepped : CPTScatterPlotInterpolationLinear;
		
		// style plots
		CPTMutableLineStyle *lineStyle = [scatterPlot.dataLineStyle mutableCopy];
		lineStyle.lineWidth = 1.0;
		lineStyle.lineColor = [CPTColor colorWithCGColor:plotColors[idx].darkerColor.CGColor];
		scatterPlot.dataLineStyle = lineStyle;

		
		NSColor* startColor = plotColors[idx].lighterColor.lighterColor.lighterColor;
		NSColor* endColor = [startColor colorWithAlphaComponent:0.75];
		CPTGradient* gradient = [CPTGradient gradientWithBeginningColor:[CPTColor colorWithCGColor:startColor.CGColor] endingColor:[CPTColor colorWithCGColor:endColor.CGColor]];
		gradient.gradientType = CPTGradientTypeAxial;
		gradient.angle = 90;

		scatterPlot.areaFill = [CPTFill fillWithGradient:gradient];
		if(self.sampleKeys.count == 2 && idx == 1)
		{
			scatterPlot.transform = CATransform3DMakeScale(1.0, -1.0, 1.0);
			scatterPlot.areaBaseValue = @10000000000000000.0;
		}
		else
		{
			scatterPlot.areaBaseValue = @0.0;
		}
		
		// set data source and add plots
		scatterPlot.dataSource = self;
		
		[rv addObject:scatterPlot];
	}];
	
	_plots = rv;
	return _plots;
}

-(NSUInteger)numberOfRecordsForPlot:(nonnull CPTPlot *)plot
{
	return [self samplesForPlotIndex:((NSNumber*)plot.identifier).unsignedIntegerValue].count;
}

-(id)numberForPlot:(CPTPlot *)plot field:(NSUInteger)fieldEnum recordIndex:(NSUInteger)index
{
	NSUInteger plotIdx = ((NSNumber*)plot.identifier).unsignedIntegerValue;
	
	if(fieldEnum == CPTScatterPlotFieldX )
	{
		return @([[[self samplesForPlotIndex:plotIdx][index] valueForKey:@"timestamp"] timeIntervalSinceReferenceDate] - [_document.recording.defactoStartTimestamp timeIntervalSinceReferenceDate]);
	}
	else
	{
		return [self transformedValueForFormatter:[[self samplesForPlotIndex:plotIdx][index] valueForKey:self.sampleKeys[plotIdx]]];
	}
}

-(nullable CPTPlotRange *)plotSpace:(nonnull CPTPlotSpace *)space willChangePlotRangeTo:(nonnull CPTPlotRange *)newRange forCoordinate:(CPTCoordinate)coordinate
{
	if(coordinate == CPTCoordinateY && _globalYRange != nil)
	{
		return _globalYRange;
	}
	
	return newRange;
}

-(void)plotSpace:(nonnull CPTPlotSpace *)space didChangePlotRangeForCoordinate:(CPTCoordinate)coordinate
{
	if(self.graph == nil || coordinate != CPTCoordinateX)
	{
		return;
	}
	
	CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
	[_delegate plotController:self didChangeToPlotRange:plotSpace.xRange];
}

- (void)setGlobalPlotRange:(CPTPlotRange*)globalPlotRange
{
	if(self.graph != nil)
	{
		[(CPTXYPlotSpace *)self.graph.defaultPlotSpace setGlobalXRange:globalPlotRange];
	}
	else
	{
		_pendingGlobalXPlotRange = globalPlotRange;
	}
}

- (void)setPlotRange:(CPTPlotRange *)plotRange
{
	if(self.graph != nil)
	{
		[(CPTXYPlotSpace *)self.graph.defaultPlotSpace setXRange:plotRange];
	}
	else
	{
		_pendingXPlotRange = plotRange;
	}
}

- (void)_zoomToScale:(CGFloat)scale
{
	[self.graph.defaultPlotSpace scaleBy:scale aboutPoint:CGPointMake(CGRectGetMidX(self.hostingView.bounds), CGRectGetMidY(self.hostingView.bounds))];
}

- (void)zoomIn
{
	[self _zoomToScale:2.0];
}

- (void)zoomOut
{
	[self _zoomToScale:0.5];
}

- (void)zoomToFitAllData
{
	[self.graph.defaultPlotSpace scaleToFitEntirePlots:_plots];
}

- (void)highlightSample:(id)sample
{
	[self _highlightSample:sample nextSample:nil plotSpaceOffset:0 notifyDelegate:YES];
}

- (void)shadowHighlightAtSampleTime:(NSTimeInterval)sampleTime
{
	[self removeHighlight];
	
	_shadowHighlightedSampleTime = sampleTime;
	
	if(self.graph == nil)
	{
		return;
	}
	
	_shadowHighlightAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:self.graph.defaultPlotSpace anchorPlotPoint:@[@0, @0]];
	_shadowLineLayer = [[DTXLineLayer alloc] initWithFrame:CGRectMake(0, 0, 15, self.requiredHeight + self.rangeInsets.bottom + self.rangeInsets.top)];
	_shadowLineLayer.lineColor = [(self.plotColors.lastObject.darkerColor) colorWithAlphaComponent:0.25];
	_shadowHighlightAnnotation.contentLayer = _shadowLineLayer;
	_shadowHighlightAnnotation.contentAnchorPoint = CGPointMake(0.5, 0.0);
	_shadowHighlightAnnotation.anchorPlotPoint = @[@(sampleTime), @(- self.rangeInsets.top)];
	
	[self.graph addAnnotation:_shadowHighlightAnnotation];
}

- (void)_highlightSample:(DTXSample*)sample nextSample:(DTXSample*)nextSample plotSpaceOffset:(CGFloat)offset notifyDelegate:(BOOL)notify
{
	if(nextSample == nil)
	{
		offset = 0.0;
	}
	
	NSTimeInterval sampleTime = sample.timestamp.timeIntervalSinceReferenceDate - _document.recording.defactoStartTimestamp.timeIntervalSinceReferenceDate + offset;
	NSUInteger sampleIdx = [[self samplesForPlotIndex:0] indexOfObject:sample];
	NSUInteger nextSampleIdx = nextSample ? [[self samplesForPlotIndex:0] indexOfObject:nextSample] : NSNotFound;
	CGFloat percent = offset / (nextSample.timestamp.timeIntervalSinceReferenceDate - sample.timestamp.timeIntervalSinceReferenceDate);
	
	[self _highlightSampleIndex:sampleIdx nextSampleIndex:nextSampleIdx sampleTime:sampleTime percect:percent makeVisible:YES];
	
	if(notify == YES && [self.delegate respondsToSelector:@selector(plotController:didHighlightAtSampleTime:)])
	{
		[self.delegate plotController:self didHighlightAtSampleTime:sampleTime];
	}
}

- (void)_highlightSampleIndex:(NSUInteger)sampleIdx nextSampleIndex:(NSUInteger)nextSampleIdx sampleTime:(NSTimeInterval)sampleTime percect:(CGFloat)percent makeVisible:(BOOL)makeVisible
{
	[self removeHighlight];
	
	_highlightedSampleIndex = sampleIdx;
	_highlightedNextSampleIndex = nextSampleIdx;
	_highlightedSampleTime = sampleTime;
	_highlightedPercent = percent;
	
	_highlightAnnotation = [[CPTPlotSpaceAnnotation alloc] initWithPlotSpace:self.graph.defaultPlotSpace anchorPlotPoint:@[@0, @0]];
	_lineLayer = [[DTXLineLayer alloc] initWithFrame:CGRectMake(0, 0, 15, self.requiredHeight + self.rangeInsets.bottom + self.rangeInsets.top)];
	_lineLayer.lineColor =  self.plotColors.count > 1 ? NSColor.blackColor : self.plotColors.firstObject.darkerColor.darkerColor;
	_highlightAnnotation.contentLayer = _lineLayer;
	_highlightAnnotation.contentAnchorPoint = CGPointMake(0.5, 0.0);
	_highlightAnnotation.anchorPlotPoint = @[@(sampleTime), @(- self.rangeInsets.top)];
	
	NSMutableArray<NSNumber*>* dataPoints = [NSMutableArray new];
	NSMutableArray<NSColor*>* pointColors = [NSMutableArray new];
	
	NSUInteger count = self.graph.allPlots.count;
	CPTXYPlotSpace *plotSpace = (CPTXYPlotSpace *)self.graph.defaultPlotSpace;
	
	[self.graph.allPlots enumerateObjectsUsingBlock:^(__kindof CPTScatterPlot * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		CGFloat value = [obj plotAreaPointOfVisiblePointAtIndex:sampleIdx].y;
		if(self.isStepped == NO && nextSampleIdx != NSNotFound)
		{
			CGFloat nextValue = [obj plotAreaPointOfVisiblePointAtIndex:nextSampleIdx].y;
			
			value = [@(value) interpolateToValue:@(nextValue) progress:percent].doubleValue;
		}
		
		value += (count - 1 - idx) * (self.graph.bounds.size.height / count + 1);
		
		if(count == 2 && idx == 1)
		{
			value = (self.graph.bounds.size.height / count) - value;
		}
		
		[dataPoints addObject:@(value)];
		[pointColors addObject:self.plotColors[idx]];
	}];
	
	_lineLayer.dataPoints = dataPoints;
	_lineLayer.pointColors = pointColors;
	
	[self.graph addAnnotation:_highlightAnnotation];
	
	if(makeVisible && (sampleTime < plotSpace.xRange.location.doubleValue || sampleTime > (plotSpace.xRange.location.doubleValue + plotSpace.xRange.length.doubleValue)))
	{
		CPTMutablePlotRange* xRange = [plotSpace.xRange mutableCopy];
		xRange.location = @(MIN(MAX(sampleTime - (xRange.length.doubleValue / 2.0), plotSpace.globalXRange.location.doubleValue), plotSpace.globalXRange.location.doubleValue + plotSpace.globalXRange.length.doubleValue));
		plotSpace.xRange = xRange;
	}
}

- (void)highlightRange:(CPTPlotRange*)range
{
	CPTScatterPlot* plot = (id)self.graph.allPlots.firstObject;
	
	[self removeHighlight];
	
	_highlightedRange = range;
	
	_rangeHighlightBand = [CPTLimitBand limitBandWithRange:range fill:[CPTFill fillWithColor:[CPTColor colorWithCGColor:self.plotColors.firstObject.darkerColor.CGColor]]];
	
	[plot addAreaFillBand:_rangeHighlightBand];
}

- (void)didFinishDrawing:(CPTPlot *)plot
{
	if(!CGRectEqualToRect(_lastDrawBounds, self.hostingView.bounds))
	{
		[self reloadHighlight];
		_lastDrawBounds = self.hostingView.bounds;
	}
}

- (void)reloadHighlight
{
	if(_shadowHighlightedSampleTime != 0.0)
	{
		[self shadowHighlightAtSampleTime:_shadowHighlightedSampleTime];
	}
	else if(_highlightedSampleIndex != NSNotFound)
	{
		[self _highlightSampleIndex:_highlightedSampleIndex nextSampleIndex:_highlightedNextSampleIndex sampleTime:_highlightedSampleTime percect:_highlightedPercent makeVisible:NO];
	}
	else if(_highlightedRange)
	{
		[self highlightRange:_highlightedRange];
	}
}

- (void)removeHighlight
{
	CPTScatterPlot* plot = (id)self.graph.allPlots.firstObject;
	
	if(_rangeHighlightBand)
	{
		[plot removeAreaFillBand:_rangeHighlightBand];
	}
	
	_rangeHighlightBand = nil;
	
	if(_shadowHighlightAnnotation && _shadowHighlightAnnotation.annotationHostLayer != nil)
	{
		[self.graph removeAnnotation:_shadowHighlightAnnotation];
	}
	
	_shadowLineLayer = nil;
	_shadowHighlightAnnotation = nil;
	
	if(_highlightAnnotation && _highlightAnnotation.annotationHostLayer != nil)
	{
		[self.graph removeAnnotation:_highlightAnnotation];
	}
	
	_lineLayer = nil;
	_highlightAnnotation = nil;
	
	_highlightedSampleIndex = NSNotFound;
	_highlightedNextSampleIndex = NSNotFound;
	_highlightedSampleTime = 0.0;
	_highlightedPercent = 0.0;
	_highlightedRange = nil;
	
	_shadowHighlightedSampleTime = 0.0;
}

- (void)noteOfSampleInsertions:(NSArray<NSNumber*>*)insertions updates:(NSArray<NSNumber*>*)updates forPlotAtIndex:(NSUInteger)index
{
	__kindof CPTPlot* plot = self.plots[index];
	
	[updates enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[plot reloadDataInIndexRange:NSMakeRange(obj.unsignedIntegerValue, 1)];
	}];
	
	__block double maxValue = 0;
	
	[[insertions sortedArrayUsingSelector:@selector(compare:)] enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[plot insertDataAtIndex:obj.unsignedIntegerValue numberOfRecords:1];
		double value = [[self numberForPlot:plot field:CPTScatterPlotFieldY recordIndex:obj.unsignedIntegerValue] doubleValue];
		if(value > maxValue)
		{
			maxValue = value;
		}
	}];
	
	CPTXYPlotSpace* plotSpace = (id)self.graph.defaultPlotSpace;
	CPTPlotRange* newYRange = [CPTPlotRange plotRangeWithLocation:@0 length:@(maxValue)];
	newYRange = [self finesedPlotRangeForPlotRange:newYRange];
	
	if(plotSpace.yRange.length.doubleValue < newYRange.length.doubleValue)
	{
		_globalYRange = newYRange;
		plotSpace.globalYRange = newYRange;
		plotSpace.yRange = newYRange;
	}
	
	[self reloadHighlight];
}

- (NSString *)displayName
{
	return @"";
}

- (NSString *)toolTip
{
	return nil;
}

- (NSImage*)displayIcon
{
	return nil;
}

- (NSImage *)smallDisplayIcon
{
	NSImage* image = [NSImage imageNamed:[NSString stringWithFormat:@"%@_small", self.displayIcon.name]];
	image.size = NSMakeSize(16, 16);
	
	return image;
}

- (NSImage *)secondaryIcon
{
    return nil;
}

- (NSFont *)titleFont
{
	return [NSFont systemFontOfSize:NSFont.systemFontSize];
}

- (CGFloat)requiredHeight
{
	return 80;
}

- (void)prepareSamples
{
	
}

- (NSArray*)samplesForPlotIndex:(NSUInteger)index
{
	return @[];
}

- (NSArray<NSString*>*)sampleKeys
{
	return @[];
}

- (NSArray<NSColor*>*)plotColors
{
	return @[];
}

- (NSArray<NSString *>*)plotTitles
{
	return @[];
}

- (CGFloat)yRangeMultiplier;
{
	return 1.15;
}

- (NSArray<CPTPlotSpaceAnnotation*>*)graphAnnotationsForGraph:(CPTGraph*)graph
{
	return @[];
}

+ (NSFormatter*)formatterForDataPresentation
{
	return [NSFormatter dtx_stringFormatter];
}

- (NSEdgeInsets)rangeInsets
{
	return NSEdgeInsetsZero;
}

- (id)transformedValueForFormatter:(id)value
{
	return value;
}

- (BOOL)isStepped
{
	return NO;
}

- (BOOL)canReceiveFocus
{
	return YES;
}

- (NSArray<NSString *> *)legendTitles
{
	return self.plotTitles;
}

- (NSArray<NSColor *> *)legendColors
{
	return self.plotColors;
}

@end