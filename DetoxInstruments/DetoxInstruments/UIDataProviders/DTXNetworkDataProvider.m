//
//  DTXNetworkDataProvider.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 12/06/2017.
//  Copyright © 2017 Wix. All rights reserved.
//

#import "DTXNetworkDataProvider.h"
#import "DTXNetworkInspectorDataProvider.h"

@implementation DTXNetworkDataProvider

+ (Class)inspectorDataProviderClass
{
	return [DTXNetworkInspectorDataProvider class];
}

- (NSArray<DTXColumnInformation *> *)columns
{
	DTXColumnInformation* duration = [DTXColumnInformation new];
	duration.title = NSLocalizedString(@"Duration", @"");
	duration.minWidth = 42;
	
	DTXColumnInformation* size = [DTXColumnInformation new];
	size.title = NSLocalizedString(@"Transferred", @"");
	size.minWidth = 60;
	
	DTXColumnInformation* responseCode = [DTXColumnInformation new];
	responseCode.title = NSLocalizedString(@"Status Code", @"");
	responseCode.minWidth = 60;
	
	DTXColumnInformation* url = [DTXColumnInformation new];
	url.title = NSLocalizedString(@"URL", @"");
//	url.minWidth = 355;
	url.automaticallyGrowsWithTable = YES;
	
	return @[duration, size, responseCode, url];
}

- (NSArray<NSNumber *> *)sampleTypes
{
	return @[@(DTXSampleTypeNetwork)];
}

- (NSString*)formattedStringValueForItem:(id)item column:(NSUInteger)column;
{
	DTXNetworkSample* networkSample = (id)item;
	
	switch(column)
	{
		case 0:
			if(networkSample.responseTimestamp == nil)
			{
				return @"--";
			}
			return [[NSFormatter dtx_durationFormatter] stringFromDate:networkSample.timestamp toDate:networkSample.responseTimestamp];
		case 1:
			if(networkSample.responseTimestamp == nil)
			{
				return @"--";
			}
			return [[NSFormatter dtx_memoryFormatter] stringForObjectValue:@(networkSample.totalDataLength)];
		case 2:
			if(networkSample.responseTimestamp == nil)
			{
				return @"--";
			}
			return [[NSFormatter dtx_stringFormatter] stringForObjectValue:@(networkSample.responseStatusCode)];
		case 3:
			return networkSample.url;
		default:
			return @"";
	}
}

@end