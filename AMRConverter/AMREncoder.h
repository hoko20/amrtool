#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AMRProgressBlock)(double progress);

typedef NS_ENUM(NSInteger, AMREncoderError) {
    AMREncoderErrorNoAudioTrack = 1,
    AMREncoderErrorReader = 2,
    AMREncoderErrorEncoder = 3,
    AMREncoderErrorFile = 4
};

FOUNDATION_EXPORT NSString *const AMREncoderErrorDomain;

/// 把任意带音轨的媒体（MP3 / MP4 / M4A / MOV / WAV / AAC 等）
/// 转成 AMR-NB 12.2 kbps / 8 kHz / 单声道的 .amr 文件。
@interface AMREncoder : NSObject

+ (BOOL)convertMediaAtURL:(NSURL *)inputURL
                    toURL:(NSURL *)outputURL
                 progress:(nullable AMRProgressBlock)progress
                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
