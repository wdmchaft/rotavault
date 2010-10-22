//
//  LCSAllDiskInfoCommandTest.m
//  rotavault
//
//  Created by Lorenz Schori on 29.09.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import <GHUnit/GHUnit.h>
#import "LCSAllDiskInfoCommand.h"
#import "LCSCommandController.h"


@interface LCSAllDiskInfoCommandTest : GHTestCase
@end


@implementation LCSAllDiskInfoCommandTest
-(void)testDiskImageInfoCommand
{
    LCSAllDiskInfoCommand *cmd = [LCSAllDiskInfoCommand command];
    
    [cmd start];
    [cmd waitUntilDone];
    
    GHAssertTrue([cmd.result isKindOfClass:[NSDictionary class]], @"Result should be a dictionary");
    GHAssertTrue([[cmd.result valueForKey:@"/dev/disk0"] isKindOfClass:[NSDictionary class]],
                 @"Result should contain at least an entry for the startup disk");
}
@end
