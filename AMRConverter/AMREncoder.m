#import "AMREncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <math.h>

// opencore-amr 的 AMR-NB 编码接口（Vendor/include 由构建脚本产出）
#import "interf_enc.h"

NSString *const AMREncoderErrorDomain = @"com.trae.amrconverter";

static const NSUInteger kAMRSamplesPerFrame = 160; // 20ms @ 8kHz

@interface AMREncoder ()
+ (void)fill:(NSError **)error code:(AMREncoderError)code message:(NSString *)message;
@end

@implementation AMREncoder

+ (BOOL)convertMediaAtURL:(NSURL *)inputURL
                    toURL:(NSURL *)outputURL
                 progress:(AMRProgressBlock)progress
                    error:(NSError **)error {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];

    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!track) {
        [self fill:error code:AMREncoderErrorNoAudioTrack message:@"这个文件里没有可用的音轨"];
        return NO;
    }

    NSError *readerError = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
    if (!reader) {
        [self fill:error code:AMREncoderErrorReader
           message:readerError.localizedDescription ?: @"无法读取该文件"];
        return NO;
    }

    // 让系统把 mp3/mp4 等音轨统一解成 AMR 需要的 8kHz 单声道 16bit PCM。
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @8000.0,
        AVNumberOfChannelsKey: @1,
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    };

    AVAssetReaderTrackOutput *output =
        [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) {
        [self fill:error code:AMREncoderErrorReader message:@"不支持这个文件的音频格式"];
        return NO;
    }
    [reader addOutput:output];

    if (![reader startReading]) {
        [self fill:error code:AMREncoderErrorReader
           message:reader.error.localizedDescription ?: @"读取失败"];
        return NO;
    }

    void *encoder = Encoder_Interface_init(0);
    if (!encoder) {
        [self fill:error code:AMREncoderErrorEncoder message:@"AMR 编码器初始化失败"];
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:outputURL error:nil];
    if (![manager createFileAtPath:outputURL.path contents:nil attributes:nil]) {
        Encoder_Interface_exit(encoder);
        [self fill:error code:AMREncoderErrorFile message:@"无法创建输出文件"];
        return NO;
    }

    NSError *handleError = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:outputURL error:&handleError];
    if (!handle) {
        Encoder_Interface_exit(encoder);
        [self fill:error code:AMREncoderErrorFile
           message:handleError.localizedDescription ?: @"输出文件不可写"];
        return NO;
    }

    static const unsigned char header[6] = {0x23, 0x21, 0x41, 0x4D, 0x52, 0x0A}; // #!AMR\n
    [handle writeData:[NSData dataWithBytes:header length:sizeof(header)]];

    const double duration = CMTimeGetSeconds(asset.duration);
    short pcm[kAMRSamplesPerFrame];
    unsigned char frame[64];
    NSUInteger filled = 0;

    while (reader.status == AVAssetReaderStatusReading) {
        @autoreleasepool {
            CMSampleBufferRef sample = [output copyNextSampleBuffer];
            if (!sample) break;

            CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
            if (block) {
                char *pointer = NULL;
                size_t total = 0;
                if (CMBlockBufferGetDataPointer(block, 0, NULL, &total, &pointer) == kCMBlockBufferNoErr
                    && pointer != NULL) {
                    const short *samples = (const short *)pointer;
                    const size_t count = total / sizeof(short);
                    for (size_t i = 0; i < count; i++) {
                        pcm[filled++] = samples[i];
                        if (filled == kAMRSamplesPerFrame) {
                            const int size = Encoder_Interface_Encode(encoder, MR122, pcm, frame, 0);
                            if (size > 0) {
                                [handle writeData:[NSData dataWithBytes:frame
                                                                 length:(NSUInteger)size]];
                            }
                            filled = 0;
                        }
                    }
                }
            }

            if (progress && duration > 0) {
                const double stamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
                if (isfinite(stamp) && stamp >= 0) {
                    progress(MIN(1.0, stamp / duration));
                }
            }

            CFRelease(sample);
        }
    }

    Encoder_Interface_exit(encoder);
    [handle closeFile];

    if (reader.status == AVAssetReaderStatusFailed) {
        [manager removeItemAtURL:outputURL error:nil];
        [self fill:error code:AMREncoderErrorReader
           message:reader.error.localizedDescription ?: @"转换过程中读取失败"];
        return NO;
    }

    if (progress) progress(1.0);
    return YES;
}

+ (void)fill:(NSError **)error code:(AMREncoderError)code message:(NSString *)message {
    if (!error) return;
    *error = [NSError errorWithDomain:AMREncoderErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message ?: @"转换失败"}];
}

@end
