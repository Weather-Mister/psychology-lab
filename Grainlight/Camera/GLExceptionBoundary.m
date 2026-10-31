#import "GLExceptionBoundary.h"
BOOL GLPerformSafely(void (NS_NOESCAPE ^block)(void), NSError **error) {
    @try { block(); return YES; }
    @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"Grainlight.CaptureSubmission" code:1
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Camera rejected the capture: %@", exception.reason ?: exception.name]}];
        return NO;
    }
}
BOOL GLExceptionBoundarySelfTest(void) {
    NSError *error = nil;
    BOOL success = GLPerformSafely(^{ [NSException raise:NSInvalidArgumentException format:@"injected submission failure"]; }, &error);
    return !success && [error.localizedDescription containsString:@"injected submission failure"];
}
