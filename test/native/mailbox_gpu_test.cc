#include "../../packages/media_kit_video/windows/mailbox_swap_chain.h"

#include <cassert>
#include <chrono>
#include <iostream>
#include <thread>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

int main() {
  Microsoft::WRL::ComPtr<ID3D11Device> device;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
  const D3D_FEATURE_LEVEL level = D3D_FEATURE_LEVEL_11_0;
  const HRESULT device_hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_WARP, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      &level, 1, D3D11_SDK_VERSION, &device, nullptr, &context);
  if (FAILED(device_hr)) {
    std::cerr << "WARP device creation failed: 0x" << std::hex << device_hr
              << "\n";
    return 1;
  }

  MailboxSwapChain* raw = nullptr;
  const HRESULT create_hr = MailboxSwapChain::Create(device.Get(), 64, 64, &raw);
  if (FAILED(create_hr)) {
    std::cerr << "D3D11 fence mailbox creation failed: 0x" << std::hex
              << create_hr << "\n";
    return 2;
  }
  Microsoft::WRL::ComPtr<MailboxSwapChain> mailbox;
  mailbox.Attach(raw);

  for (int frame = 0; frame < 128; ++frame) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(2);
    while (!mailbox->PrepareFrame()) {
      if (std::chrono::steady_clock::now() >= deadline) {
        std::cerr << "No free slot after completed WARP submissions\n";
        return 3;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    void* surface = nullptr;
    const HRESULT buffer_hr = mailbox->GetBuffer(
        0, __uuidof(ID3D11Texture2D), &surface);
    if (FAILED(buffer_hr)) {
      std::cerr << "GetBuffer failed: 0x" << std::hex << buffer_hr << "\n";
      return 4;
    }
    ID3D11Texture2D* texture = static_cast<ID3D11Texture2D*>(surface);
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> target;
    const HRESULT target_hr = device->CreateRenderTargetView(texture, nullptr,
                                                             &target);
    texture->Release();
    if (FAILED(target_hr)) return 5;
    const float color[] = {frame / 128.0f, 0.25f, 0.75f, 1.0f};
    context->ClearRenderTargetView(target.Get(), color);
    mailbox->ProducerCommit();
    for (int poll = 0; poll < 200 && mailbox->completed_sequence() <= frame;
         ++poll) {
      mailbox->ConsumerAcquire();
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    assert(mailbox->completed_sequence() > static_cast<uint64_t>(frame));
  }
  std::cout << "mailbox_gpu: 128 WARP fence-backed render cycles passed\n";
}
