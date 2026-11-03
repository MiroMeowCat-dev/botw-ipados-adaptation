#import "botw_touch_button.h"

extern void host_writes_strong_labels(TouchButton *buttons);
// The generated IR must initialize all 640 bytes before the host call and clear
// the 16 strong label fields on scope exit. This checks the actual shared type.
void verify_button_array_ownership(void) {
    TouchButton buttons[16] = {0};
    host_writes_strong_labels(buttons);
}
