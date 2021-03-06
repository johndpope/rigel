//
//  MultipeerSessionManager.m
//  Rigel
//
//  Created by Cesar Barscevicius on 5/2/16.
//  Copyright © 2016 Cesar Barscevicius. All rights reserved.
//

#import "MultipeerSessionManager.h"
#import "RigelErrorHandler.h"

#import <MultipeerConnectivity/MCSession.h>

NSString * const RigelRequestMessageKeyTitle = @"title";
NSString * const RigelRequestMessageKeyAction = @"action";
NSString * const RigelRequestMessageValueDownload = @"download";

@interface MultipeerSessionManager () <MCSessionDelegate>

@property (nonatomic, strong) MCPeerID *connectedPeerID;

@property (nonatomic, readwrite) MCSessionState state;
@property (nonatomic, strong) void (^progressBlock)(NSProgress *progress);

@end

@implementation MultipeerSessionManager

#pragma mark Init

- (instancetype)init {
    self = [self initWithSession:nil];
    return self;
}

- (instancetype)initWithSession:(MCSession *)session {
    if (self = [super init]) {
        _session = session;
        _session.delegate = self;
    }

    return self;
}

#pragma mark Getters and Setters

- (void)setSession:(MCSession *)session {
    _session = session;
    _session.delegate = self;
}

- (void)sendResourceAtURL:(NSURL *)filePath progress:(void (^)(NSProgress *progress))progressBlock withCompletion:(void (^)(NSError *))completionBlock {
    if (self.session.connectedPeers.firstObject) {
        NSProgress *progress = [self.session sendResourceAtURL:filePath withName:filePath.lastPathComponent toPeer:self.session.connectedPeers.firstObject withCompletionHandler:completionBlock];

        self.progressBlock = progressBlock;
        if (self.progressBlock) {
            [progress addObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted)) options:NSKeyValueObservingOptionInitial context:nil];
        }
    } else {
        completionBlock ([NSError errorWithDomain:RigelErrorDomain code:1004 userInfo:nil]);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (self.progressBlock && [object isKindOfClass:[NSProgress class]]) {
        self.progressBlock((NSProgress *)object);
    }
}

- (BOOL)sendData:(NSData *)data {
    if (self.session.connectedPeers.firstObject) {
        NSError *error;
        [self.session sendData:data toPeers:@[self.session.connectedPeers.firstObject] withMode:MCSessionSendDataReliable error:&error];
        if (error) {
            [RigelErrorHandler handleError:error];
            return NO;
        }
    } else {
        [RigelErrorHandler handleError:[NSError errorWithDomain:RigelErrorDomain code:1004 userInfo:nil] withCustomDescription:@"Peer seemes to be disconected."];
        return NO;
    }

    return YES;
}

#pragma mark MCSessionDelegate 

// Remote peer changed state.
- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    NSLog(@"Peer : %@ did change to :%ld", peerID, (long)state);

    if (session == self.session) {
        if (!self.connectedPeerID) {
            self.connectedPeerID = peerID;
        }

        // This delegate call might report changes in state from peers connected in the past that aready disconnected
        if (peerID == self.connectedPeerID) {
            // In case we lost connection, invalidate the current conneted peer ID
            if (state == MCSessionStateNotConnected) {
                self.connectedPeerID = nil;
            }

            // This is the peer we're connected to, let the delegate know of the change
            if ([self.delegate respondsToSelector:@selector(peer:didChangeState:)]) {
                self.state = state;
                [self.delegate peer:peerID didChangeState:state];
            }
        } else {
            NSLog(@"Supressing peer : %@ state change to :%ld", peerID, (long)state);
        }
    }
}

// Received data from remote peer.
- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    NSLog(@"Did receive data message");
    if ([self.delegate respondsToSelector:@selector(didReceiveData:)]) {
        [self.delegate didReceiveData:data];
    }
}

// Received a byte stream from remote peer.
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {

}

// Start receiving a resource from remote peer.
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress {
    NSLog(@"Did begin receiving %@", resourceName);

    if ([resourceName containsString:@".mp3"]) {
        if ([self.downloadDelegate respondsToSelector:@selector(didStartReceivingResourceWithName:withProgress:)]) {
            [self.downloadDelegate didStartReceivingResourceWithName:resourceName withProgress:progress];
        }
    }
}

// Finished receiving a resource from remote peer and saved the content
// in a temporary location - the app is responsible for moving the file
// to a permanent location within its sandbox.
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(nullable NSError *)error {
    NSLog(@"Did finish receiving %@", resourceName);
    if (![resourceName containsString:@".mp3"]) {
        if ([self.delegate respondsToSelector:@selector(didReceiveResource:atURL:)]) {
            [self.delegate didReceiveResource:resourceName atURL:localURL];
        }
    } else {
        if ([self.downloadDelegate respondsToSelector:@selector(didReceiveResource:atURL:)]) {
            [self.downloadDelegate didReceiveResource:resourceName atURL:localURL];
        }
    }
}

// Necessary due to bug on MCFramework

// Made first contact with peer and have identity information about the
// remote peer (certificate may be nil).
- (void) session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL accept))certificateHandler {
    certificateHandler(YES);
}

@end
