//
//  OCRCBZ.m
//  cbzDump
//
//  Created by david on 6/8/22.
//

#import "OCRCBZ.h"

#import "OCRUnZip.h"
#import "OCRVision.h"

#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>

@interface OCRCBZ ()
@property NSMutableDictionary<NSString *, NSString *> *pageToPageText;
@property NSMutableSet *ocrs;
@end

@implementation OCRCBZ

- (instancetype)init {
	self = [super init];
	return self;
}

- (void)ocr:(OCRVision *)ocrvision results:(id<OCRVisionResults>)ocrResults filename:(NSString *)filemame
{
	NSArray *textPieces = @[];
	if (@available(macOS 10.15, *)) {
		textPieces = ocrResults.textObservations;
		NSMutableArray *a = [NSMutableArray array];
		for (VNRecognizedTextObservation *piece in textPieces) {
			if (0.5 < piece.confidence) {
				VNRecognizedText *text1 = [[piece topCandidates:1] firstObject];
				NSString *s = text1.string;
				if (s.length) {
					[a addObject:s];
				}
			}
		}
		if (a.count) {
#if DEBUG
			[a insertObject:[NSString stringWithFormat:@"## Page %@ ##", filemame] atIndex:0];
#endif
			NSString *joined = [a componentsJoinedByString:@"\n"];
			dispatch_async(dispatch_get_main_queue(), ^{
				self.pageToPageText[filemame] = joined;
			});
		}
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.ocrs removeObject:ocrvision];
	});
}


- (NSData *)dataWithContentsOfFile:(nullable NSString *)path error:(NSError **)outErr {
	NSData *result = nil;
	OCRUnZip *unzip = [[OCRUnZip alloc] initWithZipFile:path error:outErr];
	if (unzip) {
		self.ocrs = [NSMutableSet set];
		NSArray *zipItems = unzip.items;
		self.pageToPageText = [NSMutableDictionary dictionary];
		__weak typeof(self) weakSelf = self;
		for (NSString *zipItem in zipItems) {
			@autoreleasepool {
				OCRVision *ocrVision = [[OCRVision alloc] init];
				[self.ocrs addObject:ocrVision];
				// I don't trust unzip to be thread safe.
				NSData *itemData = [unzip dataWithContentsOfFile:zipItem error:NULL];
				if (20 < itemData.length) {
					dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
						NSImage *image = [[NSImage alloc] initWithData:itemData];
						if (image) {
							[ocrVision ocrImage:image completion:^(id<OCRVisionResults> ocrResults) {
								[weakSelf ocr:ocrVision results:ocrResults filename:zipItem];
							}];
						} else {
							dispatch_async(dispatch_get_main_queue(), ^{
								[self.ocrs removeObject:ocrVision];
							});
						}
					});
				} else {
					[self.ocrs removeObject:ocrVision];
				}
				[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			}
		}
		// Wait for all ocrs to complete.
		while(self.ocrs.count != 0) {
			[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		}

		// the files in the zip aren't necessarily in sorted order.
		NSArray<NSString *> *sortedKeys = [self.pageToPageText.allKeys sortedArrayUsingSelector:@selector(compare:)];
		NSMutableArray *orderedValues = [NSMutableArray array];
		for (NSString *key in sortedKeys) {
			[orderedValues addObject:self.pageToPageText[key]];
		}
		[orderedValues addObject:@""];
		NSString *itemS = [orderedValues componentsJoinedByString:@"\n"];
		result = [itemS dataUsingEncoding:NSUTF8StringEncoding];
	}
	return result;
}



@end
