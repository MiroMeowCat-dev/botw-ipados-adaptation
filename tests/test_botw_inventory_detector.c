#include <assert.h>
#include <stdio.h>
#include "botw_inventory_detector.h"
int main(void) {
    // Actual captured inventory mask and its host's full-screen transform.
    assert(botw_inventory_scissor(15,315,1050,600));
    assert(botw_inventory_scissor(15,356,1050,490));
    assert(botw_inventory_scissor(10,210,700,400));
    assert(botw_inventory_scissor(10,238,700,326));
    // Actual non-inventory mask from the first two user captures.
    assert(!botw_inventory_scissor(1567,654,315,426));
    assert(!botw_inventory_scissor(0,0,1920,1080));
    assert(!botw_inventory_scissor(0,0,1280,720));
    assert(!botw_inventory_scissor(15,315,800,600));
    assert(!botw_inventory_scissor(15,250,1050,600));
    assert(!botw_inventory_scissor(15,315,1050,400));
    assert(!botw_inventory_scissor(UINT64_MAX,315,1050,600));
    puts("{\"captured_inventory_masks_matched\":true,\"captured_non_inventory_mask_rejected\":true,\"checks\":11}");
}
