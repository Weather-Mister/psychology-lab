#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
BOOL GLPerformSafely(void (NS_NOESCAPE ^block)(void), NSError * _Nullable * _Nullable error);
BOOL GLExceptionBoundarySelfTest(void);
NS_ASSUME_NONNULL_END
