//
//  LCSCommandLineOperationRunner.m
//  rotavault
//
//  Created by Lorenz Schori on 02.09.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSCommandLineOperationRunner.h"
#import "LCSInitMacros.h"
#import "LCSSignalHandler.h"


@implementation LCSCommandLineOperationRunner

-(id)initWithOperation:(LCSOperation *)operation
{
    LCSINIT_SUPER_OR_RETURN_NIL();

    _firstError = nil;
    _operation = [operation retain];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(_operation);
    _operation.delegate = self;

    /* setup signal handler and signal pipe */
    LCSSignalHandler *sh = [LCSSignalHandler defaultSignalHandler];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(sh);
    [sh setDelegate:self];
    [sh addSignal:SIGHUP];
    [sh addSignal:SIGINT];
    [sh addSignal:SIGPIPE];
    [sh addSignal:SIGALRM];
    [sh addSignal:SIGTERM];
    
    _statusNotificationName =
        [[NSString alloc] initWithFormat:@"ch.znerol.%@.status", [[NSProcessInfo processInfo] processName]];
    
    return self;
}

-(void)dealloc
{
    LCSSignalHandler *sh = [LCSSignalHandler defaultSignalHandler];
    [sh setDelegate:nil];

    [_firstError release];
    [_operation release];
    [super dealloc];
}

-(void)operation:(LCSOperation*)op handleException:(NSException*)exception
{
    [_operation cancel];

    NSLog(@"UNHANDLED EXCEPTION: %@:%@", [op description], [exception description]);
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [op description], @"Operation",
                              exception, @"Exception",
                              nil];
    
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:_statusNotificationName
                                                                   object:nil
                                                                 userInfo:userInfo
                                                                  options:NSNotificationPostToAllSessions];
}

-(void)operation:(LCSOperation*)op handleError:(NSError*)error
{
    if (!_firstError) {
        _firstError = [error retain];
    }

    /*
     * It is possible that self is delegate for more than the operation held in _operation. If some suboperation got
     * into trouble we cancel also the main operation (which is an instance of LCSOperationQueueOperation in the
     * typical case.
     */
    if (op != _operation) {
        [_operation cancel];
    }

    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [op description], @"Operation",
                              error, @"Error",
                              nil];
    
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:_statusNotificationName
                                                                   object:nil
                                                                 userInfo:userInfo
                                                                  options:NSNotificationPostToAllSessions];
    
    if ([error domain] == NSCocoaErrorDomain && [error code] == NSUserCancelledError) {
        return;
    }

    NSLog(@"ERROR: %@", [error localizedDescription]);
    [op cancel];
}

-(void)handleSignal:(NSNumber*)signal
{
    NSLog(@"SIGNAL: terminating on signal %d", [signal longValue]);
    [_operation cancel];
}

-(void)operation:(LCSOperation*)op updateProgress:(NSNumber*)progress
{
    NSLog(@"PROGR: %.2f", [progress floatValue]);
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              [op description], @"Operation",
                              progress, @"Progress",
                              nil];
    
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:_statusNotificationName
                                                                   object:nil
                                                                 userInfo:userInfo
                                                                  options:NSNotificationPostToAllSessions];
}

-(NSError*)run
{
    [_operation start];
    return _firstError;
}

+(NSError*)runOperation:(LCSOperation*)operation
{
    LCSCommandLineOperationRunner *runner =
        [[[LCSCommandLineOperationRunner alloc] initWithOperation:operation] autorelease];
    return [runner run];
}
@end
