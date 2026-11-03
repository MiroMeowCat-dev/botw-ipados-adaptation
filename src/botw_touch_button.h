#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

// The pinned host's -buttons: uses objc_storeStrong at label offset 24. Matching
// byte layout alone is insufficient: callers must own/initialize/destroy labels.
typedef struct { CGPoint at; uint64_t bit; __strong NSString *label; CGFloat size; } TouchButton;
_Static_assert(sizeof(TouchButton) == 40, "Pinned ARM64 TouchButton ABI changed");
_Static_assert(__builtin_offsetof(TouchButton,label) == 24, "Pinned label field offset changed");
