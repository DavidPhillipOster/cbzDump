//
//  main.m
//  cbzDump
//
//  Created by david on 6/8/22.
//

#import <Foundation/Foundation.h>

#import "OCRCBZ.h"

static void Usage(void){
	fprintf(stderr, "cbzDump [filePath.cbz]\n\tdumps all text contents of the cbz file to standard output\n");
}


int main(int argc, const char * argv[]) {
	@autoreleasepool {
	    if (1 < argc) {
				NSFileManager *fm = [NSFileManager defaultManager];
				NSString *path = [fm stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])];
				OCRCBZ *ocrCBZ = [[OCRCBZ alloc] init];
				NSError *error = nil;
				NSData *data = [ocrCBZ dataWithContentsOfFile:path error:&error];
				if (data) {
					write(1, data.bytes, data.length);
				} else {
					fprintf(stderr, "%s\n", [error.description UTF8String]);
				}
	    } else {
				Usage();
	    }
	}
	return 0;
}
