/*
 *  LCSHelperInstallRotavaultJobCommand.c
 *  rotavault
 *
 *  Created by Lorenz Schori on 18.10.10.
 *  Copyright 2010 znerol.ch. All rights reserved.
 *
 */

#include <unistd.h>
#include "LCSHelperInstallRotavaultJobCommand.h"
#include "BetterAuthorizationSampleLib.h"
#include "SampleCommon.h"

#if 1
#include <CoreServices/CoreServices.h>
#else
#warning Do not ship this way!
#include <CoreFoundation/CoreFoundation.h>
#include "/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Headers/MacErrors.h"
#endif

CFDictionaryRef LCSHelperCreateRotavaultJobDictionary(CFStringRef label, CFStringRef method, CFDateRef rundate,
                                                      CFStringRef source, CFStringRef target,
                                                      CFStringRef sourceChecksum, CFStringRef targetChecksum)
{
    CFMutableDictionaryRef plist = CFDictionaryCreateMutable(kCFAllocatorDefault, 4,
                                                             &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    CFDictionaryAddValue(plist, CFSTR("Label"), label);
    CFDictionaryAddValue(plist, CFSTR("LaunchOnlyOnce"), kCFBooleanTrue);

    CFMutableArrayRef args = CFArrayCreateMutable(kCFAllocatorDefault, 13, &kCFTypeArrayCallBacks);
    CFArrayAppendValue(args, CFSTR("/usr/local/bin/rvcopyd"));
    CFArrayAppendValue(args, CFSTR("-label"));
    CFArrayAppendValue(args, label);
    CFArrayAppendValue(args, CFSTR("-method"));
    CFArrayAppendValue(args, method);
    CFArrayAppendValue(args, CFSTR("-sourcedev"));
    CFArrayAppendValue(args, source);
    CFArrayAppendValue(args, CFSTR("-sourcecheck"));
    CFArrayAppendValue(args, sourceChecksum);
    CFArrayAppendValue(args, CFSTR("-targetdev"));
    CFArrayAppendValue(args, target);
    CFArrayAppendValue(args, CFSTR("-targetcheck"));
    CFArrayAppendValue(args, targetChecksum);
    
    CFDictionaryAddValue(plist, CFSTR("ProgramArguments"), args);
    CFRelease(args);
    
    if (rundate) {
        CFTimeZoneRef systz = CFTimeZoneCopySystem();
        CFGregorianDate gdate = CFAbsoluteTimeGetGregorianDate(CFDateGetAbsoluteTime(rundate), systz);
        CFMutableDictionaryRef caldate = CFDictionaryCreateMutable(kCFAllocatorDefault, 4,
                                                                   &kCFTypeDictionaryKeyCallBacks,
                                                                   &kCFTypeDictionaryValueCallBacks);
        
        CFNumberRef value = NULL;
        value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt8Type, &gdate.minute);
        CFDictionarySetValue(caldate, CFSTR("Minute"), value);
        CFRelease(value);
        value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt8Type, &gdate.hour);
        CFDictionarySetValue(caldate, CFSTR("Hour"), value);
        CFRelease(value);
        value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt8Type, &gdate.day);
        CFDictionarySetValue(caldate, CFSTR("Day"), value);
        CFRelease(value);
        value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt8Type, &gdate.month);
        CFDictionarySetValue(caldate, CFSTR("Month"), value);
        CFRelease(value);        

        CFDictionaryAddValue(plist, CFSTR("StartCalendarInterval"), caldate);
        
        CFRelease(caldate);
        CFRelease(systz);
    }
    else {
        CFDictionaryAddValue(plist, CFSTR("RunAtLoad"), kCFBooleanTrue);
    }
    
    return plist;
}

OSStatus LCSPropertyListWriteToFD(int fd, CFPropertyListRef plist)
{
    OSStatus retval = noErr;
    
    CFDataRef xmlData = CFPropertyListCreateXMLData(kCFAllocatorDefault, plist);
    if (xmlData == NULL) {
        retval = memFullErr;
        goto returnErr;
    }
    
    CFIndex blength = CFDataGetLength(xmlData);
    UInt8 *data = malloc(blength);
    if (data == NULL) {
        retval = memFullErr;
        goto releaseXMLAndReturnErr;
    }
    
    CFDataGetBytes(xmlData, CFRangeMake(0, blength), data);
    ssize_t bwritten = write(fd, data, blength);
    if (bwritten == -1) {
        retval = BASErrnoToOSStatus(errno);
    }
    else if (bwritten != blength) {
        retval = writErr;
    }
    
    free(data);
releaseXMLAndReturnErr:
    CFRelease(xmlData);
returnErr:    
    return noErr;
}

OSStatus LCSHelperInstallRotavaultLaunchdJob(CFDictionaryRef job)
{
    OSStatus retval = noErr;
    const char template[] = "/tmp/launchctl-XXXXXXXX";
    
    char *path = malloc(sizeof(template));
    if (path == NULL) {
        retval = memFullErr;
        goto returnErr;
    }
    
    strlcpy(path, template, sizeof(template));
    int fd = mkstemp(path);
    if (fd == -1) {
        retval = BASErrnoToOSStatus(errno);
        goto releasePathAndReturnErr;
    }
    
    retval = LCSPropertyListWriteToFD(fd, job);
    if (retval != noErr) {
        goto closeTempfileAndReturnErr;
    }
    
    char *args[] = {"/bin/launchctl", "load", path, NULL};
    
    pid_t pid = fork();
    
    if (pid == 0) {
        /* close file descriptors other than stdio in child process */
        for (int i = 3; i < getdtablesize(); i++) {
            close(i);
        }
        
        /* execute launchctl */
        execv(args[0], args);
        asl_log(NULL, NULL, ASL_LEVEL_ERR, "Failed to execute launchctl: %m");
        
        /* only reached when execve fails */
        _exit(1);
    }
    
    assert(pid > 0);
    int status;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        retval = noErr;
    }
    else {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Launchctl returned non-zero exit status");
        retval = kLCSHelperChildProcessRetunedNonZeroStatus;
    }
    
closeTempfileAndReturnErr:
    close(fd);
    unlink(path);
    
releasePathAndReturnErr:
    free(path);
returnErr:    
    return retval;
}

OSStatus LCSHelperInstallRotavaultJobCommand(CFStringRef label, CFStringRef method, CFDateRef rundate, 
                                             CFStringRef source, CFStringRef target, CFStringRef sourceChecksum,
                                             CFStringRef targetChecksum)
{
    CFDictionaryRef job = LCSHelperCreateRotavaultJobDictionary(label, method, rundate, source, target, sourceChecksum, 
                                                                targetChecksum);
    LCSHelperInstallRotavaultLaunchdJob(job);
    CFRelease(job);
    return noErr;
}
