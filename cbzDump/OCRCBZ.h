//
//  OCRCBZ.h
//  cbzDump
//
//  Created by david on 6/8/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCRCBZ : NSObject

- (nullable NSData *)dataWithContentsOfFile:(nullable NSString *)path error:(NSError * _Nullable *)outErr;

@end

NS_ASSUME_NONNULL_END
