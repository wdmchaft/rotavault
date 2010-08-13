//
//  LCSHdiUtilWithProgressOperationTest.m
//  rotavault
//
//  Created by Lorenz Schori on 08.08.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSHdiUtilWithProgressOperationTest.h"
#import "LCSHdiUtilWithProgressOperation.h"
#import "LCSHdiUtilPlistOperation.h"
#import "LCSTaskOperation+TestPassword.h"


@implementation LCSHdiUtilWithProgressOperationTest
-(void)delegateCleanup
{
    if (result) {
        [result  release];
        result = nil;
    }
    if (error) {
        [error release];
        error = nil;
    }
    progress = 0.0;
}

- (void)setUp
{
    testdir = [[LCSTestdir alloc] init];
    result = nil;
    error = nil;
}

- (void)tearDown
{
    [self delegateCleanup];
    [testdir remove];
    [testdir release];
}

-(void)operation:(LCSOperation*)operation handleError:(NSError*)inError
{
    error = [inError retain];
}

-(void)operation:(LCSTaskOperation*)operation handleResult:(id)inResult
{
    result = [inResult retain];
}

-(void)operation:(LCSOperation*)operation updateProgress:(NSNumber*)inProgress
{
    float newProgress = [inProgress floatValue];
    
    /*
     * filter out -1
     */
    if (newProgress >= 0) {
        progress = newProgress;
    }
}

-(void)testCreateEncryptedImageOperation
{
    NSString *imgpath = [[testdir path] stringByAppendingPathComponent:@"crypt.dmg"];

    LCSCreateEncryptedImageOperation *createop = [[LCSCreateEncryptedImageOperation alloc] init];
    [createop setPath:imgpath];
    [createop setSectors:2000];
    [createop setDelegate:self];

    [createop injectTestPassword:@"TEST"];

    [createop start];

    STAssertNil(error, @"Failed to create a new test-image: LCSCreateEncryptedImageOperation reported an error");
    STAssertEquals(progress, (float)100.0, @"Progress should be at 100.0 after creating the image");
    STAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:imgpath], @"Failed to create a new test-image: file "
                 @"was not created at path @%", imgpath);
    [self delegateCleanup];

    LCSAttachImageOperation *wrongop = [[LCSAttachImageOperation alloc] init];
    [wrongop setPath:imgpath];
    [wrongop bindParameter:@"result" direction:LCSParameterOut toObject:self withKeyPath:@"result"];
    [wrongop setDelegate:self];

    [wrongop injectTestPassword:@"WRONG"];

    [wrongop start];

    STAssertNotNil(error, @"LCSAttachImageOperation must report an error if password is wrong");
    STAssertEquals([error class], [LCSTaskOperationError class], @"reported error must be a "
                   @"LCSTaskOperationError");
    STAssertEquals([error code], (NSInteger)LCSExecutableReturnedNonZeroStatus, @"reported error code must be "
                   @"LCSExecutableReturnedNonZeroStatus");
    /*
    NSLog(@"localizedDescription: %@", [error localizedDescription]);
    NSLog(@"localizedFailureReason: %@", [error localizedFailureReason]);
     */
    [self delegateCleanup];

    LCSAttachImageOperation *attachop = [[LCSAttachImageOperation alloc] init];
    [attachop setPath:imgpath];
    [attachop bindParameter:@"result" direction:LCSParameterOut toObject:self withKeyPath:@"result"];
    [attachop setDelegate:self];
    
    [attachop injectTestPassword:@"TEST"];
    
    [attachop start];
    
    STAssertNil(error, @"Failed to attach test-image: LCSAttachImageOperation reported an error");
    STAssertNotNil(result, @"LCSAttachImageOperation should report results");
    STAssertTrue([result isKindOfClass:[NSDictionary class]], @"result of LCSAttachImageOperation must be a "
                 @"dictionary");
    NSString* devpath = [[[[result objectForKey:@"system-entities"] objectAtIndex:0] objectForKey:@"dev-entry"] retain];
    STAssertNotNil(devpath, @"Failed to retrieve the device path of the newly attached test image");
    [self delegateCleanup];

    LCSDetachImageOperation *detachop = [[LCSDetachImageOperation alloc] init];
    [detachop start];
    [detachop setPath:imgpath];
    [detachop bindParameter:@"result" direction:LCSParameterOut toObject:self withKeyPath:@"result"];
    [detachop setDelegate:self];
    
    [detachop start];
    
    STAssertNil(error, @"Failed to detach test-image: LCSDetachImageOperation reported an error");

    [devpath release];
    [createop release];
    [wrongop release];
    [attachop release];
    [detachop release];
}
@end
