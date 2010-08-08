//
//  LCSTestdir.m
//  rotavault
//
//  Created by Lorenz Schori on 02.08.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSTestdir.h"
#import "LCSPlistTaskOutputHandler.h"


@implementation LCSTestdir

- (LCSTestdir*) init
{
    self = [super init];

    NSTask  *mktemp = [[NSTask alloc] init];
    [mktemp setLaunchPath:@"/usr/bin/mktemp"];
    [mktemp setArguments:[NSArray arrayWithObjects:@"-d", @"/tmp/testdir_XXXXXXXX", nil]];

    NSPipe  *pipe = [[NSPipe alloc] init];
    [mktemp setStandardOutput:pipe];
    [mktemp launch];
    [mktemp waitUntilExit];

    NSData  *output = [[pipe fileHandleForReading] availableData];
    tmpdir = [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] autorelease];
    tmpdir = [[tmpdir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];

    [pipe release];
    [mktemp release];

    return self;
}

- (NSString*) path
{
    return tmpdir;
}

- (void) remove
{
    [[NSFileManager defaultManager] removeItemAtPath:tmpdir error:nil];
}

- (void) dealloc
{
    [tmpdir release];
    [super dealloc];
}

@end