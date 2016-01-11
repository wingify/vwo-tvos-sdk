//
//  VAOAPIClient.m
//  VAO
//
//  Created by Wingify on 23/08/13.
//  Copyright (c) 2013 Wingify Software Pvt. Ltd. All rights reserved.
//

#import "VAOAPIClient.h"
#import "VAOModel.h"
#import <sys/utsname.h>
#import "VAOUtils.h"
#import "AFNetworking/AFHTTPSessionManager.h"

#define kProtocol @"https://"
static float kVAOTimerInterval = 20.0;
static int kVAOPendingMessagesThreshold = 3;
static BOOL _optOut;
BOOL _previewMode;

// For queqeing of messages to be sent.
static NSInteger _transitId;
NSMutableArray *_pendingMessages;
NSMutableArray *_transittingMessages;
NSTimer *_timer;

@implementation VAOAPIClient

+ (instancetype)sharedInstance{
    static VAOAPIClient *instance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)schedule {
    _optOut = NO;
    _previewMode = NO;
    _transitId = (NSInteger) [[NSDate date] timeIntervalSinceReferenceDate];
    _pendingMessages = [NSMutableArray arrayWithArray:[[VAOModel sharedInstance] loadMessages]];
    _transittingMessages = [NSMutableArray array];
    
//    // fire first call early on to clear any pending data from last time the application was run.
    [self applicationWillEnterForeground];
}

/**
 * load pending messages from persistent storage.
 */
- (void)applicationWillEnterForeground{
    _timer = [NSTimer scheduledTimerWithTimeInterval:kVAOTimerInterval
                                              target:[VAOAPIClient sharedInstance]
                                            selector:@selector(_tick)
                                            userInfo:nil
                                             repeats:YES];
    
    // make call, so that any pending messages can be sent. Just being GREEDY!
    [self _tick];
}

/**
 * Invalidate the timer
 */
- (void)applicationDidEnterBackground {
//    [[VAOModel sharedInstance] saveMessages:_pendingMessages];
    [_timer invalidate];
    _timer = nil;
}

- (void)optOut:(BOOL)status{
    _optOut = status;
    [_pendingMessages removeAllObjects];
}

- (NSString*)convertDictionaryToString:(NSDictionary*)dictionary {
    if (!dictionary) {
        return nil;
    }
    NSError *e;
    NSData *currentData = [NSJSONSerialization dataWithJSONObject:dictionary options:kNilOptions error:&e];
    if (!e) {
        return [[NSString alloc] initWithData:currentData encoding:NSUTF8StringEncoding];
    }
    return nil;
}

// For App
- (void) pullABData:(NSMutableDictionary *)experimentsAndVariationsPair
            preview:(BOOL)isPreview
            success:(void(^)(id))successBlock
            failure:(void(^)(NSError *))failureBlock
      isSynchronous:(BOOL)synchronous {
    
    NSString *currentStr = [self convertDictionaryToString:experimentsAndVariationsPair];
    
    NSString *url = [NSString stringWithFormat:@"%@%@/mobile", kProtocol,VAO_DOMAIN];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"a"] = [VAOUtils vaoAccountId];
    parameters[@"v"] = VWO_SDK_VERSION,
    parameters[@"i"] =  [VAOUtils vaoAppKey];
    parameters[@"dt"] = [VAOUtils deviceType];
    parameters[@"os"] = [[UIDevice currentDevice] systemVersion];
    parameters[@"u"] = [VAOUtils getUUID];
    parameters[@"r"] =  @(((double)arc4random_uniform(0xffffffff))/(0xffffffff - 1));
    
    if (currentStr) {
        parameters[@"k"] = currentStr;
    }
    
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];

//#if DEBUG
//    manager.securityPolicy.allowInvalidCertificates = YES;
//    manager.securityPolicy.validatesDomainName = NO;
//#endif

    /*
    if (synchronous) {
        VAOLog(@"----------------------------------------> Downloading SYNC");
        NSError *error;
        id data = [manager syncGET:url
                               parameters:parameters
                                operation:NULL
                                    error:&error];
        if (successBlock && !error) {
            successBlock(data);
        } else if(failureBlock){
            failureBlock(error);
        }
        
    } else {
     */
        VAOLog(@"----------------------------------------> Downloading A-SYNC");
    
        [manager GET:url parameters:parameters progress:^(NSProgress * _Nonnull downloadProgress) {
            
        } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            VAOLog(@"JSON: %@", responseObject);
            if (successBlock) {
                successBlock(responseObject);
            }
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            VAOLog(@"Error: %@", error);
            if (failureBlock) {
                failureBlock(error);
            }
        }];
    /*
    }
     */
}

- (void)applicationDidEnterPreviewMode{
    _previewMode = YES;
}
- (void)applicationDidExitPreviewMode{
    _previewMode = NO;
}

- (void) pushVariationRenderWithExperimentId:(NSInteger)experimentId variationId:(NSString *)variationId{
    NSString *method = @"render";
    NSDictionary *params = @{@"expId": @(experimentId), @"varId": variationId};
    [self _call:method with:params];
}

- (void) pushGoalConversionWithGoalId:(NSInteger)goalId
                         experimentId:(NSInteger)experimentId
                          variationId:(NSString *)variationId
                              revenue:(NSNumber*)revenue {
    
    NSString *method = @"goal";
    NSDictionary *params;
    if (!revenue || revenue == (id)[NSNull null]) {
        params = @{@"goalId": @(goalId),
                   @"expId":@(experimentId),
                   @"varId": variationId};
    } else {
        params = @{@"goalId": @(goalId),
                   @"expId":@(experimentId),
                   @"varId": variationId,
                   @"revenue": revenue};
    }

    [self _call:method with:params];
}

- (void)_call:(NSString *)method with:(NSDictionary *)params{
    VAOLog(@"Called %@ with %@", method, params);
    if(_optOut == NO){
        NSString *transitId = [VAOAPIClient allocateTransitId];
        NSNumber *timestamp = @([[NSDate date] timeIntervalSince1970]);
        NSDictionary *message = @{@"method":method, @"params":params, @"timestamp":timestamp, @"id":transitId};
        [_pendingMessages addObject:message];
        [[VAOModel sharedInstance] saveMessages:[_pendingMessages copy]];
        if(_pendingMessages.count >= kVAOPendingMessagesThreshold){
            [self _tick];
        }
    }
}

- (void)sendMessage:(NSDictionary*)message
          onSuccess:(void (^)(NSString *))successBlock
          onFailure:(void (^)(NSError *, NSString*))failureBlock {
    
    NSString *transitId = message[@"id"];
    NSDictionary *params = message[@"params"];
    BOOL isRender = [message[@"method"] isEqualToString:@"render"];
    NSString *appVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    
    
    NSString *url = [kProtocol stringByAppendingString:VAO_DOMAIN];
    if(isRender) {
        url = [url stringByAppendingString:@"/l.gif"];
    } else {
        url = [url stringByAppendingString:@"/c.gif"];
    }
    
    NSDictionary *extraParams = @{@"lt": message[@"timestamp"],
                                  @"v": VWO_SDK_VERSION,
                                  @"i": [VAOUtils vaoAppKey],
                                  @"av": appVersion,
                                  @"dt": [VAOUtils deviceType],
                                  @"os": [[UIDevice currentDevice] systemVersion]
                                  };
    
    NSString *extraData = [self convertDictionaryToString:extraParams];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"experiment_id"] = params[@"expId"];
    parameters[@"account_id"] = [VAOUtils vaoAccountId];
    parameters[@"combination"] = params[@"varId"];
    parameters[@"u"] = [VAOUtils getUUID];
    parameters[@"s"] = [VAOUtils getSessionNumber]; // session
    parameters[@"random"] = @(((double)arc4random_uniform(0xffffffff))/(0xffffffff - 1));
    parameters[@"ed"] = extraData;
    
    if(isRender == NO) {
        parameters[@"goal_id"] = params[@"goalId"];
        if(params[@"revenue"]) {
            parameters[@"r"] = params[@"revenue"];
        }
    }
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
//#if DEBUG
//    manager.securityPolicy.allowInvalidCertificates = YES;
//    manager.securityPolicy.validatesDomainName = NO;
//#endif
    
    [manager GET:url parameters:parameters progress:^(NSProgress * _Nonnull downloadProgress) {
        
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        VAOLog(@"JSON: %@", responseObject);
        if (successBlock) {
            successBlock(transitId);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
        VAOLog(@"Error: %@", error);
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) task.response;
        VAOLog(@"status code: %li", (long)httpResponse.statusCode);
        if (httpResponse.statusCode == 200) {
            if (successBlock) {
                successBlock(transitId);
            }
        } else {
            if (failureBlock) {
                failureBlock(error, transitId);
            }
        }
    }];
}

/**
 * Timer operation to send messages to VAO server.
 */
- (void)_tick {
    VAOLog(@"Tick!");
    for (NSDictionary *message in _pendingMessages) {
        
        if ([_transittingMessages containsObject:message[@"id"]]) {
            // message is already being sent
            continue;
        }
        
        // add this message to transitting messages list
        [_transittingMessages addObject:[message[@"id"] copy]];
        
        
        [self sendMessage:message onSuccess:^(NSString *transitId) {
            for(int i = 0; i < _pendingMessages.count; i++){
                if([transitId isEqualToString:_pendingMessages[i][@"id"]]){
                    
                    // we are deleting from the array we are iterating over. This is generally not safe.
                    // but here it is ok as we are breaking from iteration right after deletion.
                    [_pendingMessages removeObjectAtIndex:i];
                    [_transittingMessages removeObjectIdenticalTo:transitId];
                    [[VAOModel sharedInstance] saveMessages:[_pendingMessages copy]];
                    break;
                }
            }
        } onFailure:^(NSError *error, NSString *transitId) {
            [_transittingMessages removeObjectIdenticalTo:transitId];
        }];
    }
}

-(void)dealloc{
    [_timer invalidate];
}

+ (NSString *)allocateTransitId{
    return [@(++_transitId) stringValue];
}

@end
