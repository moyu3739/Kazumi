#include "../../packages/media_kit_video/windows/frame_slots.h"
#include <cassert>
#include <iostream>

int main() {
  FrameSlots slots;
  int submitted[3];
  for (int i = 0; i < 3; ++i) {
    submitted[i] = slots.Reserve();
    assert(submitted[i] != 2 && submitted[i] >= 0);
    slots.Submit();
  }
  // A GPU delay spanning many video intervals must not overwrite any fence.
  for (int i = 0; i < 100; ++i) {
    slots.Poll([](int) { return false; });
    assert(slots.Reserve() >= 0);
    slots.Cancel();
    assert(slots.latest() == 2);
  }
  // Complete the oldest submission, although newer ones remain unfinished.
  slots.Poll([&](int slot) { return slot == submitted[0]; });
  assert(slots.sequence() == 1 && slots.latest() == submitted[0]);
  slots.AcquireLatest();
  assert(slots.Reserve() == 2);
  slots.Cancel();
  slots.Poll([&](int slot) { return slot == submitted[2]; });
  assert(slots.sequence() == 3 && slots.latest() == submitted[2]);
  // The old surface remains pinned until Flutter acquires the newer one.
  const int old_consumer = submitted[0];
  const int pinned_safe = slots.Reserve();
  assert(pinned_safe >= 0 && pinned_safe != old_consumer &&
         pinned_safe != slots.latest());
  slots.Cancel();
  slots.AcquireLatest();
  assert(slots.consumer() == submitted[2]);
  assert(slots.previous_consumer() == submitted[0]);
  const int second_safe = slots.Reserve();
  assert(second_safe >= 0 && second_safe != submitted[0] &&
         second_safe != submitted[2]);
  slots.Cancel();
  // An older late completion may free space but must never regress playback.
  slots.Poll([](int) { return true; });
  assert(slots.sequence() == 3 && slots.latest() == submitted[2]);
  for (int i = 0; i < 10000; ++i) {
    const int reserved = slots.Reserve();
    assert(reserved >= 0 && reserved != slots.latest());
    slots.Submit();
    slots.Poll([](int) { return true; });
    assert(slots.latest() == reserved);
  }
  assert(slots.sequence() == 10003);
  FrameSlots capacity;
  for (int i = 0; i < FrameSlots::kSlotCount - 1; ++i) {
    assert(capacity.Reserve() >= 0);
    capacity.Submit();
  }
  assert(capacity.Reserve() == -1);
  std::cout << "frame_slots: delayed/out-of-order fences and 10000 rotations passed\n";
}
