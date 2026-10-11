// RfxOpus -- port addition. Core Audio cannot read Ogg Opus, so .opus/.ogg files are decoded to 16-bit PCM WAV
// at import time (libopusfile, built by the GitHub workflow; see DEVIATIONS.md). Without the library
// (RFX_HAVE_OPUSFILE not defined) +available returns NO and such files are skipped.
#import <Foundation/Foundation.h>

@interface RfxOpus : NSObject
+ (BOOL)available;
// Decodes src to a WAV at dst. tags gets title/artist/album/duration (NSNumber seconds); *art gets the embedded picture if any.
+ (BOOL)DecodeFile:(NSString *)src toWav:(NSString *)dst tags:(NSMutableDictionary *)tags art:(NSData **)art;
@end
