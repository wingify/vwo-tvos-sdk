//
//  VAOModel.m
//  VAO
//
//  Created by Wingify on 26/08/13.
//  Copyright (c) 2013 Wingify Software Pvt. Ltd. All rights reserved.
//

#import "VAOModel.h"
#import "VAOAPIClient.h"
#import "VAOController.h"
#import "VAORavenClient.h"
#import "VAOUtils.h"

#define kMetaKey @"__vaojson"
#define kMessageKey @"__vaomessages"
#define kCampaignKey @"__vaocampaigns"

@implementation VAOModel

NSMutableDictionary *campaigns;
NSUserDefaults *userDefaults;

+ (instancetype)sharedInstance{
    static VAOModel *instance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    if (self = [super init]) {
        userDefaults = [NSUserDefaults standardUserDefaults];
        campaigns = [NSKeyedUnarchiver unarchiveObjectWithData:[userDefaults objectForKey:kCampaignKey]];
        campaigns = [NSMutableDictionary dictionaryWithDictionary:campaigns];
        if ([[campaigns allKeys] count] > 0) {
            [VAOUtils setIsNewVisitor:NO];
        }
    }
    return self;
}

- (void)downloadMetaWithCompletionBlock:(void(^)(NSMutableArray *meta))completionBlock
                        withCurrentMeta:(NSMutableDictionary*)currentPairs asynchronously:(BOOL)async {
    
    [[VAOAPIClient sharedInstance] pullABData:currentPairs preview:NO success:^(NSMutableArray *array) {
        
//        VAOLog(@"the json from server is = %@", array);
        
        if (completionBlock) {
            completionBlock(array);
        }
    } failure:^(NSError *error) {
        VAOLog(@"Failed to connect to the VAO server to download AB logs. %@\n", error);
    } isSynchronous:!async];
}

- (NSMutableDictionary*)loadMeta {
    return [NSMutableDictionary dictionaryWithDictionary:[NSKeyedUnarchiver unarchiveObjectWithData:[userDefaults objectForKey:kMetaKey]]];
}

- (void)saveMeta:(NSDictionary *)meta {
    /**
     * we assume that `meta` is the unabridged meta to be saved and is not polluted by any merging of old/original values.
     * Original values, in particular, may not be serializable at all, e.g., images.
     */
    @try {
        [userDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:meta] forKey:kMetaKey];
    }
    @catch (NSException *exception) {
        VAORavenCaptureException(exception);
    }
    @finally {
        
    }
}

- (NSArray *)loadMessages {
    NSArray *messages = [NSKeyedUnarchiver unarchiveObjectWithData:[userDefaults objectForKey:kMessageKey]];
    return messages;
}

- (void)saveMessages:(NSArray *)messages {
    @try {
        [userDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:messages] forKey:kMessageKey];
    }
    @catch (NSException *exception) {
        VAORavenCaptureException(exception);
    }
    @finally {
        
    }
}

/**
 *  Returns YES is user has been made part of any experiment so far
 *  Returns NO otherwise
 */
- (BOOL)isUserPartOfAnyExperiment {
    return ([[campaigns allKeys] count] > 0);
}

/**
 *  Returns YES is user has been made part of the experiment id
 *  Returns NO otherwise
 */
- (BOOL)hasBeenPartOfExperiment:(NSString*)experimentId {
    return (campaigns[experimentId] != nil && ([campaigns[experimentId][@"varId"] isEqualToString:@"0"] == NO));
}

- (NSMutableDictionary*)getCurrentExperimentsVariationPairs {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSDictionary *campaignCopy = [campaigns copy];
    
    for (NSDictionary *experimentId in campaignCopy) {
        dictionary[experimentId] = campaignCopy[experimentId][@"varId"];
    }
    return dictionary;
}

/**
    maintain list of expid-varid
    find exp-id for key,
    if this exp-id exists then already a part, otherwise make part and insert this exp id
 
 */
- (void)checkAndMakePartOfExperiment:(NSString*)experimentId variationId:(NSString*)variationId{
    if (campaigns[experimentId] == nil) {
        campaigns[experimentId] = @{@"varId":variationId};
        
        @try {
            [userDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:campaigns] forKey:kCampaignKey];
        }
        @catch (NSException *exception) {
            VAORavenCaptureException(exception);
        }
        @finally {
            
        }
        
        if ([variationId isEqualToString:@"0"] == NO) {
            [[VAOAPIClient sharedInstance] pushVariationRenderWithExperimentId:[experimentId integerValue]
                                                                   variationId:variationId];
        }

    }
}

/**
 *  Returns YES if goal has never been triggered
 *  Returns NO otherwise
 */
- (BOOL)shouldTriggerGoal:(NSString*)goalId forExperiment:(NSString*)experimentId {
    NSMutableDictionary *experimentDict = [NSMutableDictionary dictionaryWithDictionary:campaigns[experimentId]];
    NSArray *goals = experimentDict[@"goals"];
    if ([goals containsObject:goalId] == NO) {
        NSMutableArray *newGoalsArray = [NSMutableArray arrayWithArray:goals];
        [newGoalsArray addObject:goalId];
        experimentDict[@"goals"] = newGoalsArray;
        campaigns[experimentId] = experimentDict;
        [userDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:campaigns] forKey:kCampaignKey];
        return YES;
    }
    
    return NO;
}

@end
