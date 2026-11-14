// Kazumi local patch. MIT, like media_kit_video.
#ifndef MEDIA_KIT_FRAME_SLOTS_H_
#define MEDIA_KIT_FRAME_SLOTS_H_
#include <array>
#include <cstdint>
#include <cstddef>

// Producer/consumer callers provide serialization. Submitted slots are never
// recycled before completion, and the two most recently acquired handles stay
// pinned for one extra consumer turn so a queued compositor read cannot race
// producer reuse.
class FrameSlots {
 public:
  static constexpr int kSlotCount = 8;
  template <typename IsComplete> void Poll(IsComplete complete) {
    for (int i = 0; i < kSlotCount; ++i) {
      if (pending_[i] && complete(i)) {
        pending_[i] = false;
        if (serial_[i] > sequence_) {
          sequence_ = serial_[i];
          latest_ = i;
        }
      }
    }
  }
  int Reserve() {
    if (reserved_ >= 0) return reserved_;
    for (int i = 0; i < kSlotCount; ++i) {
      if (i != latest_ && i != consumer_ && i != previous_consumer_ &&
          !pending_[i]) {
        return reserved_ = i;
      }
    }
    return -1;
  }
  void Submit() {
    if (reserved_ < 0) return;
    pending_[reserved_] = true;
    serial_[reserved_] = ++submitted_;
    reserved_ = -1;
  }
  void Cancel() { reserved_ = -1; }
  void AcquireLatest() {
    if (latest_ != consumer_) {
      previous_consumer_ = consumer_;
      consumer_ = latest_;
    }
  }
  int latest() const { return latest_; }
  int consumer() const { return consumer_; }
  int previous_consumer() const { return previous_consumer_; }
  uint64_t sequence() const { return sequence_; }
 private:
  std::array<bool, kSlotCount> pending_{};
  std::array<uint64_t, kSlotCount> serial_{};
  int latest_ = 2;
  int consumer_ = -1;
  int previous_consumer_ = -1;
  int reserved_ = -1;
  uint64_t submitted_ = 0;
  uint64_t sequence_ = 0;
};
#endif
