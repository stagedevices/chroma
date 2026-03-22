#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.StageDevices.chroma";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "LaunchPrimaryText" asset catalog color resource.
static NSString * const ACColorNameLaunchPrimaryText AC_SWIFT_PRIVATE = @"LaunchPrimaryText";

/// The "LaunchSecondaryText" asset catalog color resource.
static NSString * const ACColorNameLaunchSecondaryText AC_SWIFT_PRIVATE = @"LaunchSecondaryText";

/// The "LaunchAppIcon" asset catalog image resource.
static NSString * const ACImageNameLaunchAppIcon AC_SWIFT_PRIVATE = @"LaunchAppIcon";

#undef AC_SWIFT_PRIVATE
