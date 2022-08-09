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

static int const kMaxParallelism = 5;

// Rather than the main thread, adding and removing from NSMutableSet *ocrs is serialiazed with this.
static dispatch_queue_t serialQueue;

@interface OCRCBZ ()
@property NSMutableDictionary<NSString *, NSString *> *pageToPageText;
@property NSMutableSet *ocrs;
@end

@implementation OCRCBZ

- (instancetype)init {
  self = [super init];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    serialQueue = dispatch_queue_create("serialQueue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
  });
  return self;
}

- (void)ocr:(OCRVision *)ocrvision results:(id<OCRVisionResults>)ocrResults filename:(NSString *)filename
{
  NSArray *textPieces = @[];
  if (@available(macOS 10.15, *)) {
    textPieces = ocrResults.textObservations;
    NSMutableArray *a = [NSMutableArray array];
    for (VNRecognizedTextObservation *piece in textPieces) {
      if (0.3 < piece.confidence) {
        VNRecognizedText *text1 = [[piece topCandidates:1] firstObject];
        NSString *s = text1.string;
        if (s.length) {
          [a addObject:s];
        }
      }
    }
    if (a.count) {
#if DEBUG
      [a insertObject:[NSString stringWithFormat:@"## Page %@ ##", filename] atIndex:0];
#endif
      NSString *joined = [a componentsJoinedByString:@"\n"];
      dispatch_async(serialQueue, ^{
        self.pageToPageText[filename] = joined;
      });
    }
  }
  dispatch_async(serialQueue, ^{	[self.ocrs removeObject:ocrvision];	});
}


- (NSData *)dataWithContentsOfFile:(nullable NSString *)path error:(NSError **)outErr {
  NSData *result = nil;
  OCRUnZip *unzip = [[OCRUnZip alloc] initWithZipFile:path error:outErr];
  if (unzip) {
    self.ocrs = [NSMutableSet set];
    NSArray *zipItems = unzip.items;
    self.pageToPageText = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    dispatch_group_t group = dispatch_group_create();
    for (NSString *zipItem in zipItems) {
      @autoreleasepool {
        OCRVision *ocrVision = [[OCRVision alloc] init];
        // adding is synchronous so it is certain to be in the map before anything else happens.
        dispatch_sync(serialQueue, ^{
          [self.ocrs addObject:ocrVision];
        });
        // I don't trust unzip to be thread safe.
        NSData *itemData = [unzip dataWithContentsOfFile:zipItem error:NULL];
        if (20 < itemData.length) {
          dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            NSImage *image = [[NSImage alloc] initWithData:itemData];
            if (image) {
              [ocrVision ocrImage:image completion:^(id<OCRVisionResults> ocrResults) {
                [weakSelf ocr:ocrVision results:ocrResults filename:zipItem];
              }];
            } else {
              dispatch_async(serialQueue, ^{	[self.ocrs removeObject:ocrVision];	});
            }
          });
        } else {
          dispatch_async(serialQueue, ^{	[self.ocrs removeObject:ocrVision];	});
        }
        // Don't just swamp the queue with tasks: limit it to a small multiple of the number of cores.
        // It's OK that I'm not guarding access to self.ocrs.count, since I only need an approximately correct value.
        while(kMaxParallelism < self.ocrs.count) {
          [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
      }
    }
    // Wait for all ocr blocks to complete.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    while (self.ocrs.count != 0) {
      [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    // the files in the zip aren't necessarily in sorted order.
    NSArray<NSString *> *sortedKeys = [self.pageToPageText.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
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
