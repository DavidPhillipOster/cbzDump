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
			// Next line For debugging.
			[a insertObject:[NSString stringWithFormat:@"## Page %@ ##", filemame] atIndex:0];
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
		NSMutableArray *imageFiles = [NSMutableArray array];
		self.pageToPageText = [NSMutableDictionary dictionary];
		for (NSString *zipItem in zipItems) {
			NSData *itemData = [unzip dataWithContentsOfFile:zipItem error:NULL];
			if (20 < itemData.length) {
				NSImage *image = [[NSImage alloc] initWithData:itemData];
				if (image) {
					OCRVision *ocrVision = [[OCRVision alloc] init];
					[self.ocrs addObject:ocrVision];
					__weak typeof(self) weakSelf = self;
					dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
						NSString *zipItem1 = zipItem;
						[ocrVision ocrImage:image completion:^(id<OCRVisionResults> ocrResults) {
							[weakSelf ocr:ocrVision results:ocrResults filename:zipItem1];
						}];
					});
					[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
					[imageFiles addObject:zipItem];
				}
			}
		}

		while(self.ocrs.count != 0) {
			[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		}

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
