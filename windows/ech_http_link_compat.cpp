#include <stddef.h>

extern "C" void* __cdecl RtlSetVolatileMemory(void* destination,
                                                unsigned char value,
                                                size_t size) {
  auto* dst = static_cast<volatile unsigned char*>(destination);
  for (size_t i = 0; i < size; ++i) {
    dst[i] = value;
  }
  return destination;
}

extern "C" size_t __cdecl __std_mismatch_1(const void* first,
                                             const void* second,
                                             size_t count) {
  const auto* a = static_cast<const unsigned char*>(first);
  const auto* b = static_cast<const unsigned char*>(second);
  for (size_t i = 0; i < count; ++i) {
    if (a[i] != b[i]) {
      return i;
    }
  }
  return count;
}
