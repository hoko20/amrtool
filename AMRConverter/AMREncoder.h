#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AMRProgressBlock)(double progress);

typedef NS_ENUM(NSInteger, AMREncoderError) {
    AMREncoderErrorNoAudioTrack = 1,
    AMREncoderErrorReader = 2,
    AMREncoderErrorEncoder = 3,
    AMREncoderErrorFile = 4
};

/// 输出编码格式
typedef NS_ENUM(NSInteger, AMROutputFormat) {
    AMROutputFormatNB = 0,   ///< AMR-NB 12.2 kbps / 8 kHz，兼容性最好
    AMROutputFormatWB = 1,   ///< AMR-WB 23.85 kbps / 16 kHz，明显更清晰
    AMROutputFormatSilk = 2, ///< SILK v3 25 kbps / 24 kHz，微信 / QQ 语音
};

FOUNDATION_EXPORT NSString *const AMREncoderErrorDomain;

/// 把任意带音轨的媒体（MP3 / MP4 / M4A / MOV / WAV / AAC 等）转成 AMR 或 SILK。
@interface AMREncoder : NSObject

+ (BOOL)convertMediaAtURL:(NSURL *)inputURL
                    toURL:(NSURL *)outputURL
                   format:(AMROutputFormat)format
                 progress:(nullable AMRProgressBlock)progress
                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
