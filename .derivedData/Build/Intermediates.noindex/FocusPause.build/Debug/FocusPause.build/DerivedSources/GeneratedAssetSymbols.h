#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.lizhirui.FocusPause";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "MenuBarIcon" asset catalog image resource.
static NSString * const ACImageNameMenuBarIcon AC_SWIFT_PRIVATE = @"MenuBarIcon";

/// The "MenuBarStatusTemplate" asset catalog image resource.
static NSString * const ACImageNameMenuBarStatusTemplate AC_SWIFT_PRIVATE = @"MenuBarStatusTemplate";

#undef AC_SWIFT_PRIVATE
