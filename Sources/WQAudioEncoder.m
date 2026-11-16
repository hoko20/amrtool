//
//  WQAudioEncoder.m
//  SandboxExplorer
//

#import "WQAudioEncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <math.h>
#import <string.h>

#import "interf_enc.h"        // AMR-NB（opencore-amr）
#import "enc_if.h"            // AMR-WB（vo-amrwbenc）
#import "SKP_Silk_SDK_API.h"  // SILK v3

NSString *const WQAudioEncoderErrorDomain = @"dev.local.SandboxExplorer.audio";

typedef NS_ENUM(NSInteger, WQAudioEncoderError) {
    WQAudioEncoderErrorNoAudioTrack = 1,
    WQAudioEncoderErrorReader = 2,
    WQAudioEncoderErrorEncoder = 3,
    WQAudioEncoderErrorFile = 4,
};

typedef struct {
    WQAudioEncodeFormat format;
    NSUInteger frameSamples;
    void *nbState;
    void *wbState;
    void *silkState;
    SKP_SILK_SDK_EncControlStruct silkControl;
    NSUInteger encodedFrames;
} WQEncoderContext;

static int WQEncoderSampleRate(WQAudioEncodeFormat format)
{
    switch (format) {
        case WQAudioEncodeFormatAMRNB: return 8000;
        case WQAudioEncodeFormatAMRWB: return 16000;
        case WQAudioEncodeFormatSilk:  return 24000;
    }
    return 8000;
}

static void WQEncoderWriteHeader(NSFileHandle *handle, WQAudioEncodeFormat format)
{
    static const unsigned char nb[]   = {0x23, 0x21, 0x41, 0x4D, 0x52, 0x0A};
    static const unsigned char wb[]   = {0x23, 0x21, 0x41, 0x4D, 0x52, 0x2D, 0x57, 0x42, 0x0A};
    static const unsigned char silk[] = {0x02, 0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B,
                                         0x5F, 0x56, 0x33};

    const unsigned char *bytes = nb;
    NSUInteger length = sizeof(nb);
    if (format == WQAudioEncodeFormatAMRWB) {
        bytes = wb;
        length = sizeof(wb);
    } else if (format == WQAudioEncodeFormatSilk) {
        bytes = silk;
        length = sizeof(silk);
    }
    [handle writeData:[NSData dataWithBytes:bytes length:length]];
}

static BOOL WQEncoderInit(WQEncoderContext *ctx, NSString **message)
{
    switch (ctx->format) {
        case WQAudioEncodeFormatAMRNB:
            ctx->nbState = Encoder_Interface_init(0);
            if (!ctx->nbState) {
                *message = @"AMR-NB 编码器初始化失败";
                return NO;
            }
            return YES;

        case WQAudioEncodeFormatAMRWB:
            ctx->wbState = E_IF_init();
            if (!ctx->wbState) {
                *message = @"AMR-WB 编码器初始化失败";
                return NO;
            }
            return YES;

        case WQAudioEncodeFormatSilk: {
            SKP_int size = 0;
            if (SKP_Silk_SDK_Get_Encoder_Size(&size) != 0 || size <= 0) {
                *message = @"SILK 编码器初始化失败";
                return NO;
            }
            ctx->silkState = malloc((size_t)size);
            SKP_SILK_SDK_EncControlStruct status;
            memset(&status, 0, sizeof(status));
            if (!ctx->silkState || SKP_Silk_SDK_InitEncoder(ctx->silkState, &status) != 0) {
                free(ctx->silkState);
                ctx->silkState = NULL;
                *message = @"SILK 编码器初始化失败";
                return NO;
            }

            memset(&ctx->silkControl, 0, sizeof(ctx->silkControl));
            ctx->silkControl.API_sampleRate = 24000;
            ctx->silkControl.maxInternalSampleRate = 24000;
            ctx->silkControl.packetSize = 480;   // 20ms @ 24kHz
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

static void WQEncoderRelease(WQEncoderContext *ctx)
{
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

static BOOL WQEncoderEncodeFrame(WQEncoderContext *ctx, NSFileHandle *handle, const short *pcm)
{
    unsigned char payload[1024];
    int size = -1;

    switch (ctx->format) {
        case WQAudioEncodeFormatAMRNB:
            size = Encoder_Interface_Encode(ctx->nbState, MR122, pcm, payload, 0);
            break;
        case WQAudioEncodeFormatAMRWB:
            size = E_IF_encode(ctx->wbState, 8, pcm, payload, 0);   // mode 8 = 23.85 kbps
            break;
        case WQAudioEncodeFormatSilk: {
            SKP_int16 bytes = (SKP_int16)sizeof(payload);
            if (SKP_Silk_SDK_Encode(ctx->silkState, &ctx->silkControl, pcm,
                                    (SKP_int16)ctx->frameSamples, payload, &bytes) == 0) {
                size = bytes;
            }
            break;
        }
    }

    if (size <= 0) return NO;

    if (ctx->format == WQAudioEncodeFormatSilk) {
        // 微信 / QQ 语音条：每帧前置 2 字节小端长度
        int16_t little = (int16_t)size;
        [handle writeData:[NSData dataWithBytes:&little length:sizeof(little)]];
    }
    [handle writeData:[NSData dataWithBytes:payload length:(NSUInteger)size]];
    ctx->encodedFrames++;
    return YES;
}

static void WQEncoderFill(NSError **error, WQAudioEncoderError code, NSString *message)
{
    if (!error) return;
    *error = [NSError errorWithDomain:WQAudioEncoderErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message ?: @"转换失败"}];
}

@implementation WQAudioEncoder

+ (BOOL)convertURL:(NSURL *)inputURL
             toURL:(NSURL *)outputURL
            format:(WQAudioEncodeFormat)format
          progress:(WQAudioProgressBlock)progress
             error:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track) {
        WQEncoderFill(error, WQAudioEncoderErrorNoAudioTrack, @"这个文件里没有可用的音轨");
        return NO;
    }

    NSError *readerError = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
    if (!reader) {
        WQEncoderFill(error, WQAudioEncoderErrorReader,
                      readerError.localizedDescription ?: @"无法读取该文件");
        return NO;
    }

    const int sampleRate = WQEncoderSampleRate(format);
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc]
        initWithTrack:track
      outputSettings:@{
          AVFormatIDKey: @(kAudioFormatLinearPCM),
          AVSampleRateKey: @(sampleRate),
          AVNumberOfChannelsKey: @1,
          AVLinearPCMBitDepthKey: @16,
          AVLinearPCMIsFloatKey: @NO,
          AVLinearPCMIsBigEndianKey: @NO,
          AVLinearPCMIsNonInterleaved: @NO,
      }];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) {
        WQEncoderFill(error, WQAudioEncoderErrorReader, @"不支持这个文件的音频格式");
        return NO;
    }
    [reader addOutput:output];

    if (![reader startReading]) {
        WQEncoderFill(error, WQAudioEncoderErrorReader,
                      reader.error.localizedDescription ?: @"读取失败");
        return NO;
    }

    [manager removeItemAtURL:outputURL error:nil];
    if (![manager createFileAtPath:outputURL.path contents:nil attributes:nil]) {
        WQEncoderFill(error, WQAudioEncoderErrorFile, @"无法创建输出文件");
        return NO;
    }

    NSError *handleError = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:outputURL error:&handleError];
    if (!handle) {
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorFile,
                      handleError.localizedDescription ?: @"输出文件不可写");
        return NO;
    }

    WQEncoderWriteHeader(handle, format);

    WQEncoderContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.format = format;
    ctx.frameSamples = (NSUInteger)(sampleRate / 50);   // 20ms

    NSString *initMessage = nil;
    if (!WQEncoderInit(&ctx, &initMessage)) {
        [handle closeFile];
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorEncoder, initMessage ?: @"编码器初始化失败");
        return NO;
    }

    short pcm[960];
    NSUInteger filled = 0;
    const double duration = CMTimeGetSeconds(asset.duration);
    BOOL encoderFailed = NO;

    while (reader.status == AVAssetReaderStatusReading) {
        @autoreleasepool {
            CMSampleBufferRef sample = [output copyNextSampleBuffer];
            if (!sample) break;

            CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
            if (block) {
                size_t total = CMBlockBufferGetDataLength(block);
                NSMutableData *copy = [NSMutableData dataWithLength:total];
                if (total > 0 && copy
                    && CMBlockBufferCopyDataBytes(block, 0, total, copy.mutableBytes) == kCMBlockBufferNoErr) {
                    const short *samples = copy.bytes;
                    const size_t count = total / sizeof(short);
                    for (size_t i = 0; i < count && !encoderFailed; i++) {
                        pcm[filled++] = samples[i];
                        if (filled == ctx.frameSamples) {
                            if (!WQEncoderEncodeFrame(&ctx, handle, pcm)) encoderFailed = YES;
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

    // 不足一帧的尾部补零编码，避免丢掉最后一个音头
    if (!encoderFailed && filled > 0) {
        for (NSUInteger i = filled; i < ctx.frameSamples; i++) pcm[i] = 0;
        if (!WQEncoderEncodeFrame(&ctx, handle, pcm)) encoderFailed = YES;
    }

    WQEncoderRelease(&ctx);
    [handle closeFile];

    if (encoderFailed) {
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorEncoder, @"编码过程中出错，可能是源音频格式异常");
        return NO;
    }

    if (reader.status == AVAssetReaderStatusFailed) {
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorReader,
                      reader.error.localizedDescription ?: @"转换过程中读取失败");
        return NO;
    }

    if (ctx.encodedFrames == 0) {
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorReader,
                      @"没有解出任何音频数据，可能是纯视频（无音轨）或格式不被支持");
        return NO;
    }

    if (progress) progress(1.0);
    return YES;
}

+ (BOOL)exportM4AURL:(NSURL *)inputURL
               toURL:(NSURL *)outputURL
            progress:(WQAudioProgressBlock)progress
               error:(NSError **)error
{
    NSFileManager *manager = NSFileManager.defaultManager;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    if ([asset tracksWithMediaType:AVMediaTypeAudio].count == 0) {
        WQEncoderFill(error, WQAudioEncoderErrorNoAudioTrack, @"这个文件里没有可用的音轨");
        return NO;
    }

    AVAssetExportSession *session = [[AVAssetExportSession alloc]
        initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!session) {
        WQEncoderFill(error, WQAudioEncoderErrorReader, @"系统不支持导出 M4A");
        return NO;
    }

    [manager removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    session.outputFileType = AVFileTypeAppleM4A;
    session.shouldOptimizeForNetworkUse = YES;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(semaphore);
    }];

    while (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) != 0) {
        if (progress) progress(session.progress);
    }

    if (session.status != AVAssetExportSessionStatusCompleted) {
        [manager removeItemAtURL:outputURL error:nil];
        WQEncoderFill(error, WQAudioEncoderErrorEncoder,
                      session.error.localizedDescription ?: @"M4A 导出失败");
        return NO;
    }

    if (progress) progress(1.0);
    return YES;
}

@end
