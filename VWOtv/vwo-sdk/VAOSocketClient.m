//
//  VAOSocketClient.m
//  VAO
//
//  Created by Wingify on 10/02/14.
//  Copyright (c) 2014 Wingify Software Pvt. Ltd. All rights reserved.
//

#import "VAOSocketClient.h"
#import <VWOtv/VWOtv-Swift.h>
#import "VAOController.h"
#import "VAOUtils.h"

#define kSocketIP @"https://mobilepreview.vwo.com:443"
@implementation VAOSocketClient{
    SocketIOClient *socket;
}

+ (instancetype)sharedInstance{
    
    static VAOSocketClient *instance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)launch {
    socket = [[SocketIOClient alloc] initWithSocketURL:kSocketIP options:@{@"log": @YES, @"forcePolling": @YES}];
    
    [socket on:@"connect" callback:^(NSArray* data, SocketAckEmitter* ack) {
        VAOLog(@"print this on successful connection");
        VAOLog(@"[[UIDevice currentDevice] name] = %@", [[UIDevice currentDevice] name] );
        NSDictionary *dict  = @{@"name":[[UIDevice currentDevice] name],
                                @"type": @"iOS",
                                @"appKey": [VAOUtils vaoAppKey]};
        
        [socket emit:@"register_mobile" withItems:@[dict]];
        
        [self initMethods];
    }];
    
    [socket connect];
}

-(void)initMethods {
    
    [socket on:@"disconnect" callback:^(NSArray *data, SocketAckEmitter *ack) {
        VAOLog(@"socket disconnected");
        [[VAOController sharedInstance] applicationDidExitPreviewMode];
    }];
    
    
    [socket on:@"error" callback:^(NSArray *data, SocketAckEmitter *ack) {
        VAOLog(@"error in connection = %@", data);
    }];
    
    [socket on:@"browser_connect" callback:^(NSArray *data, SocketAckEmitter *ack) {
        VAOLog(@"in browser_connect");
        [[VAOController sharedInstance] applicationDidEnterPreviewMode];
        id object = [data firstObject];
        if (object && object[@"name"]) {
            NSLog(@"|------------------------------------------------------------------------|");
            NSLog(@"|------         VWO: In preview mode. Connected with:%@            ------|", object[@"name"]);
            NSLog(@"|------------------------------------------------------------------------|");
        }
    }];
    
    [socket on:@"browser_disconnect" callback:^(NSArray *data, SocketAckEmitter *ack) {
        VAOLog(@"in browser_disconnect");
        NSLog(@"|------------------------------------------------------------------------|");
        NSLog(@"|------         VWO: In preview mode. DIS Connected                ------|");
        NSLog(@"|------------------------------------------------------------------------|");
        [[VAOController sharedInstance] applicationDidExitPreviewMode];
    }];
    
    [socket on:@"receive_variation" callback:^(NSArray *data, SocketAckEmitter *ack) {
        
        VAOLog(@"receive_variation arugments = %@", data);
        id expObject = [data firstObject];
        
        // check for sanity of expObject
        if (!expObject || !expObject[@"variationId"]) {
            VAOLog(@"receive_variation ERROR");
        }
        
        [socket emit:@"receive_variation_success" withItems:[NSArray arrayWithObject:@{@"variationId":expObject[@"variationId"]}]];
        
        if (data.count) {
            [[VAOController sharedInstance] previewMeta:[data firstObject]];
            
            NSLog(@"VWO: In preview mode. Variation Received :%@", [data firstObject][@"json"]);
        }
    }];
    
    /*
    __weak id socket_ = socket;
    socket.onConnect = ^{
        VAOLog(@"print this on successful connection");
        VAOLog(@"[[UIDevice currentDevice] name] = %@", [[UIDevice currentDevice] name] );
        NSDictionary *dict  = @{@"name":[[UIDevice currentDevice] name],
                                @"type": @"iOS",
                                @"appKey": [VAOUtils vaoAppKey]};
        
        [socket_ emit:@"register_mobile" args:[NSArray arrayWithObject:dict]];
    };
    

    
    socket.onConnectError = ^(NSDictionary *error) {
        VAOLog(@"error in connection = %@", error);
    };
    
    socket.onError = ^(NSDictionary *error) {
        VAOLog(@"error = %@", error);
    };
    
    [socket on:@"browser_connect" callback:^(SIOParameterArray *arguments) {
        VAOLog(@"in browser_connect");
        [[VAOController sharedInstance] applicationDidEnterPreviewMode];
        id object = [arguments firstObject];
        if (object && object[@"name"]) {
            NSLog(@"|------------------------------------------------------------------------|");
            NSLog(@"|------         VWO: In preview mode. Connected with:%@            ------|", object[@"name"]);
            NSLog(@"|------------------------------------------------------------------------|");
        }
    }];

    [socket on:@"browser_disconnect" callback:^(SIOParameterArray *arguments) {
        VAOLog(@"in browser_disconnect");
        NSLog(@"|------------------------------------------------------------------------|");
        NSLog(@"|------         VWO: In preview mode. DIS Connected                ------|");
        NSLog(@"|------------------------------------------------------------------------|");
        [[VAOController sharedInstance] applicationDidExitPreviewMode];
    }];
    
    [socket on:@"receive_variation" callback:^(SIOParameterArray *arguments) {
        
        VAOLog(@"receive_variation arugments = %@", arguments);
        id expObject = [arguments firstObject];
        
        // check for sanity of expObject
        if (!expObject || !expObject[@"variationId"]) {
            VAOLog(@"receive_variation ERROR");
        }
        
        [socket emit:@"receive_variation_success" args:[NSArray arrayWithObject:@{@"variationId":expObject[@"variationId"]}]];
        
        if (arguments.count) {
            [[VAOController sharedInstance] previewMeta:[arguments firstObject]];
            
            NSLog(@"VWO: In preview mode. Variation Received :%@", [arguments firstObject][@"json"]);
        }
    }];
     */
}

- (void)goalTriggeredWithName:(NSString*)goal {
    NSDictionary *dict = @{@"goal":goal};
    [socket emit:@"goal_triggered" withItems:@[dict]];
}

- (void)goalTriggeredWithName:(NSString*)goal withValue:(double)value {
    NSDictionary *dict = @{@"goal":goal,
                           @"value":@(value)};
    [socket emit:@"goal_triggered" withItems:@[dict]];
}

@end
