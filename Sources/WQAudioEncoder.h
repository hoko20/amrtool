//
//  WQAudioEncoder.h
//  SandboxExplorer
//
//  AMR-NB / AMR-WB / SILK 编码与 M4A 导出。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WQAudioProgressBlock)(double progress);

typedef NS_ENUM(NSInteger, WQAudioEncodeFormat) {
    WQAudioEncodeFormatAMRNB = 0,
    WQAudioEncodeFormatAMRWB = 1,
    WQAudioEncodeFormatSilk = 2,
};

FOUNDATION_EXPORT NSString *const WQAudioEncoderErrorDomain;

@interface WQAudioEncoder : NSObject

/// 取音轨 -> 重采样为单声道 16bit -> 逐帧编码，自动补足不足 20ms 的尾帧。
+ (BOOL)convertURL:(NSURL *)inputURL
             toURL:(NSURL *)outputURL
            format:(WQAudioEncodeFormat)format
          progress:(nullable WQAudioProgressBlock)progress
             error:(NSError *_Nullable *_Nullable)error;

/// AAC 96 kbps M4A。
+ (BOOL)exportM4AURL:(NSURL *)inputURL
               toURL:(NSURL *)outputURL
            progress:(nullable WQAudioProgressBlock)progress
               error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
