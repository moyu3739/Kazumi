// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "mailbox_swap_chain.h"

#include <iostream>

MailboxSwapChain::~MailboxSwapChain() {
  ReleaseSlots();
}

HRESULT MailboxSwapChain::Create(ID3D11Device* device,
                                  int32_t width,
                                  int32_t height,
                                  MailboxSwapChain** out) {
  if (!device || !out) return E_INVALIDARG;

  auto* p = new (std::nothrow) MailboxSwapChain();
  if (!p) return E_OUTOFMEMORY;

  p->device_ = device;
  p->width_ = (width > 0) ? width : 1;
  p->height_ = (height > 0) ? height : 1;

  {
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> ctx;
    device->GetImmediateContext(&ctx);
    const HRESULT hr2 = ctx.As(&p->context4_);
    if (FAILED(hr2)) {
      std::cout << "media_kit: MailboxSwapChain: ID3D11DeviceContext4 not available "
                   "(hr=0x" << std::hex << hr2 << std::dec << ")" << std::endl;
      delete p;
      return hr2;
    }
  }

  const HRESULT hr = p->AllocateSlots();
  if (FAILED(hr)) {
    delete p;
    return hr;
  }

  // libmpv may request a target while creating its render context.
  p->write_slot_ = p->frame_slots_.Reserve();

  *out = p;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE MailboxSwapChain::QueryInterface(REFIID riid,
                                                            void** ppv) {
  if (!ppv) return E_POINTER;

  if (riid == __uuidof(IUnknown) || riid == __uuidof(IDXGIObject) ||
      riid == __uuidof(IDXGIDeviceSubObject) ||
      riid == __uuidof(IDXGISwapChain)) {
    *ppv = static_cast<IDXGISwapChain*>(this);
    AddRef();
    return S_OK;
  }

  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MailboxSwapChain::AddRef() {
  return ref_count_.fetch_add(1u, std::memory_order_relaxed) + 1u;
}

ULONG STDMETHODCALLTYPE MailboxSwapChain::Release() {
  const ULONG prev = ref_count_.fetch_sub(1u, std::memory_order_acq_rel);
  if (prev == 1u) delete this;
  return prev - 1u;
}

HRESULT STDMETHODCALLTYPE MailboxSwapChain::GetBuffer(UINT Buffer,
                                                       REFIID riid,
                                                       void** ppSurface) {
  if (!ppSurface) return E_POINTER;
  if (Buffer != 0 || write_slot_ < 0) return DXGI_ERROR_INVALID_CALL;

  if (riid != __uuidof(ID3D11Texture2D) &&
      riid != __uuidof(ID3D11Resource)) {
    return E_NOINTERFACE;
  }

  ID3D11Texture2D* tex = slots_[write_slot_].texture.Get();
  if (!tex) return E_FAIL;

  tex->AddRef();
  *ppSurface = tex;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE
MailboxSwapChain::GetDesc(DXGI_SWAP_CHAIN_DESC* pDesc) {
  if (!pDesc) return E_POINTER;
  *pDesc = {};
  pDesc->BufferDesc.Width = static_cast<UINT>(width_);
  pDesc->BufferDesc.Height = static_cast<UINT>(height_);
  pDesc->BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  pDesc->BufferCount = 1;
  pDesc->SampleDesc.Count = 1;
  pDesc->BufferUsage =
      DXGI_USAGE_RENDER_TARGET_OUTPUT | DXGI_USAGE_SHADER_INPUT;
  pDesc->Windowed = TRUE;
  pDesc->SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
  return S_OK;
}

void MailboxSwapChain::PollCompleted() {
  frame_slots_.Poll([&](int slot) {
    const auto value = slots_[slot].fence->GetCompletedValue();
    // UINT64_MAX reports device removal, not successful completion.
    return value != UINT64_MAX && value >= slots_[slot].fence_value;
  });
  latest_completed_slot_.store(frame_slots_.latest(), std::memory_order_release);
  completed_sequence_.store(frame_slots_.sequence(), std::memory_order_release);
}

bool MailboxSwapChain::PrepareFrame() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  PollCompleted();
  write_slot_ = frame_slots_.Reserve();
  return write_slot_ >= 0;
}

void MailboxSwapChain::ProducerCommit() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  if (write_slot_ < 0) return;
  auto& slot = slots_[write_slot_];
  const auto hr = context4_->Signal(slot.fence.Get(), ++slot.fence_value);
  if (SUCCEEDED(hr)) {
    frame_slots_.Submit();
    // A fence is useless if its command buffer remains unsubmitted.
    context4_->Flush();
  } else {
    frame_slots_.Cancel();
  }
  write_slot_ = -1;
  PollCompleted();
}

HANDLE MailboxSwapChain::ConsumerAcquire() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  // Also poll here: the last video frame must become visible even if mpv
  // has not yet sent the next update (e.g. pause / low frame rate).
  PollCompleted();
  // Keep Flutter's current shared texture out of the producer's writable
  // pool until Flutter asks for a different completed frame.
  frame_slots_.AcquireLatest();
  return slots_[frame_slots_.latest()].shared_handle;
}

HANDLE MailboxSwapChain::ReadHandleSnapshot() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  frame_slots_.AcquireLatest();
  latest_completed_slot_.store(frame_slots_.latest(), std::memory_order_release);
  return slots_[frame_slots_.latest()].shared_handle;
}

HRESULT MailboxSwapChain::Resize(int32_t width, int32_t height) {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  ReleaseSlots();
  width_ = (width > 0) ? width : 1;
  height_ = (height > 0) ? height : 1;
  frame_slots_ = FrameSlots{};
  completed_sequence_ = 0;
  latest_completed_slot_.store(2, std::memory_order_relaxed);
  write_slot_ = frame_slots_.Reserve();
  return AllocateSlots();
}

HRESULT MailboxSwapChain::AllocateSlots() {
  Microsoft::WRL::ComPtr<ID3D11Device5> device5;
  {
    const HRESULT hr =
        device_->QueryInterface(__uuidof(ID3D11Device5), (void**)&device5);
    if (FAILED(hr)) {
      std::cout << "media_kit: MailboxSwapChain: ID3D11Device5 not available "
                   "(hr=0x" << std::hex << hr << std::dec << ")" << std::endl;
      return hr;
    }
  }

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.CPUAccessFlags = 0;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  for (int i = 0; i < FrameSlots::kSlotCount; ++i) {
    HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &slots_[i].texture);
    if (FAILED(hr)) {
      std::cout << "media_kit: MailboxSwapChain: CreateTexture2D slot " << i
                << " failed (hr=0x" << std::hex << hr << std::dec << ")"
                << std::endl;
      return hr;
    }

    Microsoft::WRL::ComPtr<IDXGIResource> resource;
    hr = slots_[i].texture.As(&resource);
    if (FAILED(hr)) {
      std::cout << "media_kit: MailboxSwapChain: As<IDXGIResource> slot " << i
                << " failed (hr=0x" << std::hex << hr << std::dec << ")"
                << std::endl;
      return hr;
    }

    hr = resource->GetSharedHandle(&slots_[i].shared_handle);
    if (FAILED(hr)) {
      std::cout << "media_kit: MailboxSwapChain: GetSharedHandle slot " << i
                << " failed (hr=0x" << std::hex << hr << std::dec << ")"
                << std::endl;
      return hr;
    }

    hr = device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                              __uuidof(ID3D11Fence),
                              (void**)&slots_[i].fence);
    if (FAILED(hr)) {
      std::cout << "media_kit: MailboxSwapChain: CreateFence slot " << i
                << " failed (hr=0x" << std::hex << hr << std::dec << ")"
                << std::endl;
      return hr;
    }
    slots_[i].fence_value = 0;
  }

  return S_OK;
}

void MailboxSwapChain::ReleaseSlots() {
  for (auto& slot : slots_) {
    slot.texture.Reset();
    slot.shared_handle = nullptr;
    slot.fence.Reset();
    slot.fence_value = 0;
  }
}
