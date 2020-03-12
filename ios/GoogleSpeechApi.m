#import <AVFoundation/AVFoundation.h>
#import "google/cloud/speech/v1/CloudSpeech.pbrpc.h"
#import "AudioController.h"
#import "SpeechRecognitionService.h"

#import "GoogleSpeechApi.h"

@interface GoogleSpeechApi () <AudioControllerDelegate>

@property (nonatomic, strong) NSMutableData *audioData;
@property (nonatomic, strong) AudioController *audioController;
@property (nonatomic, assign) double sampleRate;

@end

@implementation GoogleSpeechApi

RCT_EXPORT_MODULE()

#pragma mark - EXPORT METHODS

RCT_EXPORT_METHOD(setApiKey:(NSString *)apiKey) {
    [SpeechRecognitionService sharedInstance].apiKey = apiKey;
}

RCT_EXPORT_METHOD(setSpeechContextPhrases:(NSArray<NSString *> *)speechContextPhrases) {
    [SpeechRecognitionService sharedInstance].speechContextPhrases = speechContextPhrases;
}

RCT_EXPORT_METHOD(start) {
    [self startSpeech:false];
}

RCT_EXPORT_METHOD(stop) {
    [self stopSpeech];
}

#pragma mark - Overwrites

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = 16000.0f;
        [SpeechRecognitionService sharedInstance].sampleRate = _sampleRate;
        _audioController = [[AudioController alloc] initWithSampleRate:_sampleRate];
        OSStatus osStatus = [_audioController prepare];
        NSError *error = [self errorForOSStatus:osStatus];
        if (error) {
            [self handleStartError:error];
        }
    }
    return self;
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (NSArray<NSString *>*)supportedEvents {
    return @[@"onSpeechRecognized", @"onSpeechRecognizedError", @"onStartError", @"onStopError"];
}

#pragma mark - Private

- (void)startSpeech:(BOOL)isNewIOUnit {
    self.audioController.delegate = self;
    self.audioData = [[NSMutableData alloc] init];
    
    OSStatus osStatus = noErr;
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:&error]) {
        [self handleStartError:error];
        [self stopSpeech];
        return;
    }
    
    osStatus = [self.audioController start];
    error = [self errorForOSStatus:osStatus];
    // Do not go further if there was no error during start.
    if (!error) {
        return;
    }
    
    // Do not go further if there was an error during start new Remote IO Unit
    if (isNewIOUnit) {
        [self handleStartError:error];
        [self stopSpeech];
        return;
    }
    
    // Otherwise recreate IOUnit.
    osStatus = [self.audioController recreateIOUnit];
    error = [self errorForOSStatus:osStatus];
    
    // Try once again to start speech if recreation of IOUnit succeded.
    // Handle error otherwise.
    if (!error) {
        [self startSpeech:YES];
    } else {
        [self handleStartError:error];
        [self stopSpeech];
    }
}

- (void)stopSpeech {
    [[SpeechRecognitionService sharedInstance] stopStreaming];
    OSStatus osStatus = [self.audioController stop];
    NSError *error = [self errorForOSStatus:osStatus];
    if (error) {
        [self handleStopError:error];
    }
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error]) {
        [self handleStopError:error];
    }
    self.audioController.delegate = nil;
}

- (NSError *)errorForOSStatus:(OSStatus)osStatus {
    if (osStatus == 0) {
        return nil;
    }
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:osStatus userInfo:nil];
}

- (void)handleStopError:(NSError *)error {
    [self sendError:error viaEventWithName:@"onStopError"];
}

- (void)handleStartError:(NSError *)error {
    [self sendError:error viaEventWithName:@"onStartError"];
}

- (void)sendError:(NSError *)error viaEventWithName:(NSString *)eventName  {
    [self sendEventWithName:eventName body:@{@"message": error.localizedDescription, @"code": @(error.code)}];
}

#pragma mark - AudioControllerDelegate

- (void)processSampleData:(NSData *)data {
    [self.audioData appendData:data];
    NSInteger frameCount = [data length] / 2;
    int16_t *samples = (int16_t *) [data bytes];
    int64_t sum = 0;
    for (int i = 0; i < frameCount; i++) {
        sum += abs(samples[i]);
    }
    
    // We recommend sending samples in 100ms chunks
    int chunk_size = 0.1 /* seconds/chunk */ * self.sampleRate * 2 /* bytes/sample */ ; /* bytes/chunk */
    
    if ([self.audioData length] > chunk_size) {
        [[SpeechRecognitionService sharedInstance]
         streamAudioData:self.audioData
         withCompletion:^(StreamingRecognizeResponse *response, NSError *error) {
            if (error) {
                [self sendEventWithName:@"onSpeechRecognizedError"
                                   body:@{@"message": error.localizedDescription, @"isFinal":@YES}];
                [self stopSpeech];
            } else if (response) {
                BOOL finished = NO;
                for (StreamingRecognitionResult *result in response.resultsArray) {
                    if (result.isFinal) {
                        finished = YES;
                    }
                }
                NSString *transcript = response.resultsArray.firstObject.alternativesArray.firstObject.transcript;
                [self sendEventWithName:@"onSpeechRecognized"
                                   body:@{@"text": transcript, @"isFinal":@(finished)}];
                if (finished) {
                    [self stopSpeech];
                }
            }
        }];
        self.audioData = [[NSMutableData alloc] init];
    }
}

@end
