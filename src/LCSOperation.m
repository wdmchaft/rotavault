//
//  LCSOperation.m
//  rotavault
//
//  Created by Lorenz Schori on 11.08.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSOperation.h"

@implementation LCSOperation

-(id)init
{
    self = [super init];
    delegate = nil;
    name = [[NSNull null] retain];
    _runBeforeMain = [[NSMutableArray alloc] init];
    _runAfterMain = [[NSMutableArray alloc] init];
    return self;
}

-(void)dealloc
{
    [name release];
    [super dealloc];
}

@synthesize name;
@synthesize delegate;

/* main thread */
-(void)updateBoundInParameter:(NSString*)parameter atObject:(id)obj withKeyPath:(NSString*)keyPath
{
        [self setValue:[obj valueForKeyPath:keyPath] forKey:parameter];
}

/* main thread */
-(void)updateBoundOutParameter:(NSString*)parameter atObject:(id)obj withKeyPath:(NSString*)keyPath
{
    [obj setValue:[self valueForKey:parameter] forKeyPath:keyPath];
}

/* client code */
-(void)bindParameter:(NSString*)parameter direction:(LCSParameterDirection)direction toObject:(id)obj withKeyPath:(NSString*)keyPath
{
    if (direction & LCSParameterIn) {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                             [self methodSignatureForSelector:@selector(updateBoundInParameter:atObject:withKeyPath:)]];

        [inv setSelector:@selector(updateBoundInParameter:atObject:withKeyPath:)];
        [inv setArgument:&parameter atIndex:2];
        [inv setArgument:&obj atIndex:3];
        [inv setArgument:&keyPath atIndex:4];
        [inv retainArguments];

        [_runBeforeMain addObject:inv];
    }
    if(direction == LCSParameterOut) {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                             [self methodSignatureForSelector:@selector(updateBoundOutParameter:atObject:withKeyPath:)]];

        [inv setSelector:@selector(updateBoundOutParameter:atObject:withKeyPath:)];
        [inv setArgument:&parameter atIndex:2];
        [inv setArgument:&obj atIndex:3];
        [inv setArgument:&keyPath atIndex:4];
        [inv retainArguments];

        [_runAfterMain addObject:inv];
    }
}

/* client code */
-(void)setParameter:(NSString*)parameter to:(id)value
{
    [self setValue:value forKey:parameter];
}

/* override */
-(void)updateProgress:(float)progress
{
    [self delegateSelector:@selector(operation:updateProgress:)
             withArguments:[NSArray arrayWithObjects:self, [NSNumber numberWithFloat:progress], nil]];
}

/* override */
-(void)handleError:(NSError*)error
{
    [self delegateSelector:@selector(operation:handleError:)
             withArguments:[NSArray arrayWithObjects:self, error, nil]];
}

/* perform a selector on the delegate in main thread */
-(void)delegateSelector:(SEL)selector withArguments:(NSArray*)arguments
{
    /* nothing to perform if there is no delegate */
    if (delegate == nil) {
        return;
    }

    /* nothing to perform if the delegate does not respond to the specified selector */
    NSMethodSignature *sig = [delegate methodSignatureForSelector:selector];
    if (sig == nil) {
        return;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:selector];

    NSInteger argIndex=2;
    for(id arg in arguments) {
        [inv setArgument:&arg atIndex:argIndex++];
    }

    @try {
        [inv performSelectorOnMainThread:@selector(invokeWithTarget:) withObject:delegate waitUntilDone:YES];
    }
    @catch (NSException * e) {
        NSLog(@"Failed to perform delegate method: %@", [e description]);
    }
}

-(void)execute
{
    /* override */
}

-(void)main
{
    /* check for cancelation */
    if ([self isCancelled]) {
        return;
    }

    /* populate in-parameters (with values from main thread) */
    for(NSInvocation *inv in _runBeforeMain) {
        @try {        
            [inv performSelectorOnMainThread:@selector(invokeWithTarget:) withObject:self waitUntilDone:YES];
        }
        @catch (NSException * e) {
            NSLog(@"Failed to update in-parameter: %@", [e description]);
        }
    }

    /* perforrm operation */
    [self execute];
    
    /* write results out (on main thread) */
    for(NSInvocation *inv in _runAfterMain) {
        @try {        
            [inv performSelectorOnMainThread:@selector(invokeWithTarget:) withObject:self waitUntilDone:YES];
        }
        @catch (NSException * e) {
            NSLog(@"Failed to update out-parameter: %@", [e description]);
        }            
    }        
}

-(void)cancel
{
    NSError *cancelError = [NSError errorWithDomain:NSCocoaErrorDomain
                                               code:NSUserCancelledError
                                           userInfo:[NSDictionary dictionary]];
    [self handleError:cancelError];
    [super cancel];
}
@end
