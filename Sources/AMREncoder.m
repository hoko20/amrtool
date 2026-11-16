#import "AMREncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <math.h>
#import <string.h>

// 三个编码器头文件由 scripts/build-opencore-amr.sh 产出到 Vendor/include
#import "interf_enc.h"        // AMR-NB（opencore-amr）
#import "enc_if.h"            // AMR-WB（vo-amrwbenc）
#import "SKP_Silk_SDK_API.h"  // SILK v3（腾讯语音）

NSString *const AMREncoderErrorDomain = @"com.trae.amrconverter";

#pragma mark - 编码器上下文

typedef struct {
    AMROutputFormat format;
    NSUInteger frameSamples;      // 20ms 采样数
    void *nbState;
    void *wbState;
    void *silkState;
    SKP_SILK_SDK_EncControlStruct silkControl;
    NSUInteger encodedFrames;
} AMREncoderContext;

static int AMRSampleRate(AMROutputFormat format) {
    switch (format) {
        case AMROutputFormatNB:   return 8000;
        case AMROutputFormatWB:   return 16000;
        case AMROutputFormatSilk: return 24000;
    }
    return 8000;
}

static void AMRWriteHeader(NSFileHandle *handle, AMROutputFormat format) {
    static const unsigned char nbHeader[] = {0x23, 0x21, 0x41, 0x4D, 0x52, 0x0A};              // #!AMR\n
    static const unsigned char wbHeader[] = {0x23, 0x21, 0x41, 0x4D, 0x52, 0x2D, 0x57, 0x42, 0x0A}; // #!AMR-WB\n
    static const unsigned char silkHeader[] = {0x02, 0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B,
                                               0x5F, 0x56, 0x33};                                  // \x02#!SILK_V3

    switch (format) {
        case AMROutputFormatNB:
            [handle writeData:[NSData dataWithBytes:nbHeader length:sizeof(nbHeader)]];
            break;
        case AMROutputFormatWB:
            [handle writeData:[NSData dataWithBytes:wbHeader length:sizeof(wbHeader)]];
            break;
        case AMROutputFormatSilk:
            [handle writeData:[NSData dataWithBytes:silkHeader length:sizeof(silkHeader)]];
            break;
    }
}

static BOOL AMRInitEncoder(AMREncoderContext *ctx, NSString **message) {
    switch (ctx->format) {
        case AMROutputFormatNB:
            ctx->nbState = Encoder_Interface_init(0);
            if (!ctx->nbState) {
                *message = @"AMR-NB 编码器初始化失败";
                return NO;
            }
            return YES;

        case AMROutputFormatWB:
            ctx->wbState = E_IF_init();
            if (!ctx->wbState) {
                *message = @"AMR-WB 编码器初始化失败";
                return NO;
            }
            return YES;

        case AMROutputFormatSilk: {
            SKP_int size = 0;
            if (SKP_Silk_SDK_Get_Encoder_Size(&size) != 0 || size <= 0) {
                *message = @"SILK 编码器初始化失败";
                return NO;
            }
            ctx->silkState = malloc((size_t)size);
            SKP_SILK_SDK_EncControlStruct status;
            memset(&status, 0, sizeof(status));
            if (!ctx->silkState || SKP_Silk_SDK_InitEncoder(ctx->silkState, &status) != 0) {
                *message = @"SILK 编码器初始化失败";
                return NO;
            }

            memset(&ctx->silkControl, 0, sizeof(ctx->silkControl));
            ctx->silkControl.API_sampleRate = 24000;
            ctx->silkControl.maxInternalSampleRate = 24000;
            ctx->silkControl.packetSize = 480;   // 20ms @24kHz
            ctx->silkControl.bitRate = 25000;
            ctx->silkControl.packetLossPercentage = 0;
            ctx->silkControl.complexity = 2;
            ctx->silkControl.useInBandFEC = 0;
            ctx->silkControl.useDTX = 0;
            return YES;
        }
    }
    return NO;
}

static void AMRReleaseEncoder(AMREncoderContext *ctx) {
    if (ctx->nbState) {
        Encoder_Interface_exit(ctx->nbState);
        ctx->nbState = NULL;
    }
    if (ctx->wbState) {
        E_IF_exit(ctx->wbState);
        ctx->wbState = NULL;
    }
    if (ctx->silkState) {
        free(ctx->silkState);
        ctx->silkState = NULL;
    }
}

/// 编码一帧并写入文件；返回 NO 表示编码器报错。
static BOOL AMREncodeFrame(AMREncoderContext *ctx, NSFileHandle *handle,
                           const short *pcm, int *lastSize) {
    unsigned char payload[1024];
    int size = -1;

    switch (ctx->format) {
        case AMROutputFormatNB:
            size = Encoder_Interface_Encode(ctx->nbState, MR122, pcm, payload, 0);
            break;
        case AMROutputFormatWB:
            // mode 8 = 23.85 kbps，AMR-WB 最高档
            size = E_IF_encode(ctx->wbState, 8, pcm, payload, 0);
            break;
        case AMROutputFormatSilk: {
            SKP_int16 bytes = (SKP_int16)sizeof(payload);
            if (SKP_Silk_SDK_Encode(ctx->silkState, &ctx->silkControl, pcm,
                                    (SKP_int16)ctx->frameSamples, payload, &bytes) == 0) {
                size = bytes;
            }
            break;
        }
    }

    if (size <= 0) return NO;

    if (ctx->format == AMROutputFormatSilk) {
        // 微信 / QQ 的每帧格式：2 字节小端长度 + 帧数据
        int16_t little = (int16_t)size;
        [handle writeData:[NSData dataWithBytes:&little length:sizeof(little)]];
    }
    [handle writeData:[NSData dataWithBytes:payload length:(NSUInteger)size]];
    ctx->encodedFrames++;
    if (lastSize) *lastSize = size;
    return YES;
}

#pragma mark - AMREncoder

@implementation AMREncoder

+ (BOOL)convertMediaAtURL:(NSURL *)inputURL
                    toURL:(NSURL *)outputURL
                   format:(AMROutputFormat)format
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

    // 让系统按目标格式重采样：NB 8k / WB 16k / SILK 24k，统一单声道 16bit
    const int sampleRate = AMRSampleRate(format);
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(sampleRate),
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

    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:outputURL error:nil];
    if (![manager createFileAtPath:outputURL.path contents:nil attributes:nil]) {
        [self fill:error code:AMREncoderErrorFile message:@"无法创建输出文件"];
        return NO;
    }

    NSError *handleError = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:outputURL error:&handleError];
    if (!handle) {
        [self fill:error code:AMREncoderErrorFile
           message:handleError.localizedDescription ?: @"输出文件不可写"];
        return NO;
    }

    AMRWriteHeader(handle, format);

    AMREncoderContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.format = format;
    ctx.frameSamples = (NSUInteger)(sampleRate / 50); // 20ms

    NSString *initMessage = nil;
    if (!AMRInitEncoder(&ctx, &initMessage)) {
        [handle closeFile];
        [manager removeItemAtURL:outputURL error:nil];
        [self fill:error code:AMREncoderErrorEncoder message:initMessage ?: @"编码器初始化失败"];
        return NO;
    }

    short pcm[960]; // 48kHz 时的 20ms 上限，实际按 frameSamples 使用
    NSUInteger filled = 0;
    const double duration = CMTimeGetSeconds(asset.duration);
    BOOL encoderFailed = NO;

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
                    for (size_t i = 0; i < count && !encoderFailed; i++) {
                        pcm[filled++] = samples[i];
                        if (filled == ctx.frameSamples) {
                            if (!AMREncodeFrame(&ctx, handle, pcm, NULL)) {
                                encoderFailed = YES;
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
        if (encoderFailed) break;
    }

    AMRReleaseEncoder(&ctx);
    [handle closeFile];

    if (encoderFailed) {
        [manager removeItemAtURL:outputURL error:nil];
        [self fill:error code:AMREncoderErrorEncoder message:@"编码过程中出错，可能是源音频格式异常"];
        return NO;
    }

    if (reader.status == AVAssetReaderStatusFailed) {
        [manager removeItemAtURL:outputURL error:nil];
        [self fill:error code:AMREncoderErrorReader
           message:reader.error.localizedDescription ?: @"转换过程中读取失败"];
        return NO;
    }

    if (ctx.encodedFrames == 0) {
        [manager removeItemAtURL:outputURL error:nil];
        [self fill:error code:AMREncoderErrorReader
           message:@"没有解出任何音频数据，可能是纯视频（无音轨）或格式不被支持"];
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
