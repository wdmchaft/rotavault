//
//  LCSPlistExternalCommandTest.m
//  rotavault
//
//  Created by Lorenz Schori on 25.09.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import <GHUnit/GHUnit.h>
#import "LCSQuickExternalCommand.h"
#import "LCSCommandController.h"
#import "LCSCommandManager.h"
#import "LCSPlistExternalCommand.h"
#import "LCSTestdir.h"


@interface LCSPlistExternalCommandTest : GHTestCase {
    NSMutableArray *states;
    LCSCommandManager *mgr;
    LCSQuickExternalCommand *cmd;
    LCSCommandController *ctl;
}
@end


@implementation LCSPlistExternalCommandTest

-(void)setUp
{
    states = [[NSMutableArray alloc] init];
    
    mgr = [[LCSCommandManager alloc] init];
    cmd = [[LCSPlistExternalCommand alloc] init];
    ctl = [[LCSCommandController controllerWithCommand:cmd] retain];
    
    [mgr addCommandController:ctl];
    [ctl addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionInitial context:nil];
}

-(void)tearDown
{
    [ctl removeObserver:self forKeyPath:@"state"];
    [mgr removeCommandController:ctl];
    
    [ctl release];
    ctl = nil;
    [cmd release];
    cmd = nil;
    [mgr release];
    mgr = nil;
    
    [states release];
    states = nil;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object != ctl) {
        return;
    }
    
    if ([keyPath isEqualToString:@"state"]) {
        [states addObject:[NSNumber numberWithInt:ctl.state]];
    }
}

-(void)testCommandWithPlistStdout
{
    LCSTestdir *testdir = [[LCSTestdir alloc] init];
    NSString *testscript = [[testdir path] stringByAppendingPathComponent:@"test.sh"];
    NSString *plistContents = 
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<string>HELLO</string>\n"
        @"</plist>\n";
    
    NSString *scriptContents = [NSString stringWithFormat:
                                @"#!/bin/sh\n"
                                @"cat <<'EOF'\n"
                                @"%@\n"
                                @"EOF", plistContents];
                                
    
    BOOL result = [scriptContents writeToFile:testscript atomically:NO encoding:NSUTF8StringEncoding error:nil];
    
    GHAssertEquals(result, YES, @"Failed to write helper script");
    
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSDictionary *executableAttribute = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0755]
                                                                    forKey:NSFilePosixPermissions];
    result = [fm setAttributes:executableAttribute ofItemAtPath:testscript error:nil];
    GHAssertEquals(result, YES, @"Failed to chmod helper script");
    
    [cmd.task setLaunchPath:@"/bin/sh"];
    [cmd.task setArguments:[NSArray arrayWithObject:testscript]];
    [ctl start];
    
    [mgr waitUntilAllCommandsAreDone];
    
    NSArray *expectedStates = [NSArray arrayWithObjects:
                               [NSNumber numberWithInt:LCSCommandStateInit],
                               [NSNumber numberWithInt:LCSCommandStateStarting],
                               [NSNumber numberWithInt:LCSCommandStateRunning],
                               [NSNumber numberWithInt:LCSCommandStateFinished],
                               [NSNumber numberWithInt:LCSCommandStateInvalidated],
                               nil];
    
    GHAssertEqualObjects(states, expectedStates, @"Unexpected state sequence");
    
    GHAssertEqualObjects(ctl.result, @"HELLO", @"Unexpected result");
    
    [fm release];
    [testdir remove];
    [testdir release];
}

-(void)testCommandWithInvalidStdout
{
    [cmd.task setLaunchPath:@"/bin/echo"];
    [cmd.task setArguments:[NSArray arrayWithObject:@"no plist here!"]];
    [ctl start];
    
    [mgr waitUntilAllCommandsAreDone];
    
    NSArray *expectedStates = [NSArray arrayWithObjects:
                               [NSNumber numberWithInt:LCSCommandStateInit],
                               [NSNumber numberWithInt:LCSCommandStateStarting],
                               [NSNumber numberWithInt:LCSCommandStateRunning],
                               [NSNumber numberWithInt:LCSCommandStateFailed],
                               [NSNumber numberWithInt:LCSCommandStateInvalidated],
                               nil];
    
    GHAssertEqualObjects(states, expectedStates, @"Unexpected state sequence");
}

@end
