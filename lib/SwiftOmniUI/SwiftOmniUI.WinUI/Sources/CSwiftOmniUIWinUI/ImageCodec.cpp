// SPDX-License-Identifier: Apache-2.0
#include "Relay.h"
#include <wincodec.h>
#include <shlwapi.h>
#include <vector>
#include <memory>
#include <cstring>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Storage.Streams.h>

using namespace swiftomniui;
namespace {
    using Bytes = std::vector<uint8_t>;
    winrt::com_ptr<IWICImagingFactory> imaging() {
        winrt::com_ptr<IWICImagingFactory> factory;
        winrt::check_hresult(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.put())));
        return factory;
    }
    winrt::fire_and_forget provideImage(
        winrt::Windows::ApplicationModel::DataTransfer::DataProviderRequest request, std::shared_ptr<Bytes> bytes) {
        using namespace winrt::Windows::Storage::Streams;
        auto deferral = request.GetDeferral();
        try {
            InMemoryRandomAccessStream stream;
            DataWriter writer(stream); writer.WriteBytes(*bytes);
            co_await writer.StoreAsync(); writer.DetachStream(); stream.Seek(0);
            request.SetData(RandomAccessStreamReference::CreateFromStream(stream));
        } catch (...) { report("providing a clipboard image"); }
        deferral.Complete();
    }

}
extern "C" void *swiftomniui_winui_decode_image(uint8_t const *bytes, int64_t count, int32_t *size) {
    try {
        if (!bytes || !size || count <= 0 || count > MAXDWORD) return nullptr;
        auto factory = imaging();
        winrt::com_ptr<IWICStream> stream; winrt::check_hresult(factory->CreateStream(stream.put()));
        winrt::check_hresult(stream->InitializeFromMemory(const_cast<BYTE *>(bytes), static_cast<DWORD>(count)));
        winrt::com_ptr<IWICBitmapDecoder> decoder;
        winrt::check_hresult(factory->CreateDecoderFromStream(stream.get(), nullptr, WICDecodeMetadataCacheOnLoad, decoder.put()));
        winrt::com_ptr<IWICBitmapFrameDecode> frame; winrt::check_hresult(decoder->GetFrame(0, frame.put()));
        winrt::com_ptr<IWICFormatConverter> converter; winrt::check_hresult(factory->CreateFormatConverter(converter.put()));
        winrt::check_hresult(converter->Initialize(frame.get(), GUID_WICPixelFormat32bppPRGBA,
            WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom));
        UINT width = 0, height = 0; winrt::check_hresult(converter->GetSize(&width, &height));
        if (!width || !height || width > 16384 || height > 16384) return nullptr;
        auto result = std::make_unique<Bytes>(static_cast<size_t>(width) * height * 4);
        winrt::check_hresult(converter->CopyPixels(nullptr, width * 4, static_cast<UINT>(result->size()), result->data()));
        size[0] = static_cast<int32_t>(width); size[1] = static_cast<int32_t>(height);
        return result.release();
    } catch (...) { report("decoding an in-memory image"); return nullptr; }
}
extern "C" void *swiftomniui_winui_encode_png(uint8_t const *rgba, int32_t width, int32_t height, int64_t *count) {
    try {
        if (!rgba || !count || width <= 0 || height <= 0 || width > 16384 || height > 16384) return nullptr;
        auto factory = imaging();
        winrt::com_ptr<IStream> stream; winrt::check_hresult(CreateStreamOnHGlobal(nullptr, TRUE, stream.put()));
        winrt::com_ptr<IWICBitmapEncoder> encoder; winrt::check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.put()));
        winrt::check_hresult(encoder->Initialize(stream.get(), WICBitmapEncoderNoCache));
        winrt::com_ptr<IWICBitmapFrameEncode> frame; winrt::check_hresult(encoder->CreateNewFrame(frame.put(), nullptr));
        winrt::check_hresult(frame->Initialize(nullptr)); winrt::check_hresult(frame->SetSize(width, height));
        // PNG stores straight alpha. Convert through WIC's normal pixel converter.
        winrt::com_ptr<IWICBitmap> bitmap;
        winrt::check_hresult(factory->CreateBitmapFromMemory(width, height, GUID_WICPixelFormat32bppPRGBA,
            width * 4, static_cast<UINT>(width) * height * 4, const_cast<BYTE *>(rgba), bitmap.put()));
        winrt::com_ptr<IWICFormatConverter> converter; winrt::check_hresult(factory->CreateFormatConverter(converter.put()));
        winrt::check_hresult(converter->Initialize(bitmap.get(), GUID_WICPixelFormat32bppRGBA,
            WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom));
        WICPixelFormatGUID format = GUID_WICPixelFormat32bppRGBA; winrt::check_hresult(frame->SetPixelFormat(&format));
        if (!IsEqualGUID(format, GUID_WICPixelFormat32bppRGBA)) return nullptr;
        winrt::check_hresult(frame->WriteSource(converter.get(), nullptr));
        winrt::check_hresult(frame->Commit()); winrt::check_hresult(encoder->Commit());
        STATSTG stat{}; winrt::check_hresult(stream->Stat(&stat, STATFLAG_NONAME));
        if (stat.cbSize.QuadPart > MAXDWORD) return nullptr;
        auto result = std::make_unique<Bytes>(static_cast<size_t>(stat.cbSize.QuadPart));
        LARGE_INTEGER zero{}; winrt::check_hresult(stream->Seek(zero, STREAM_SEEK_SET, nullptr));
        ULONG read = 0; winrt::check_hresult(stream->Read(result->data(), static_cast<ULONG>(result->size()), &read));
        if (read != result->size()) return nullptr;
        *count = static_cast<int64_t>(result->size()); return result.release();
    } catch (...) { report("encoding an in-memory PNG"); return nullptr; }
}
extern "C" bool swiftomniui_winui_image_bytes(void *image, uint8_t *output, int64_t count) {
    auto bytes = static_cast<Bytes *>(image);
    if (!bytes || !output || count != static_cast<int64_t>(bytes->size())) return false;
    std::memcpy(output, bytes->data(), bytes->size()); return true;
}
extern "C" void swiftomniui_winui_image_bytes_close(void *image) { delete static_cast<Bytes *>(image); }
extern "C" void swiftomniui_winui_copy_image(uint8_t const *png, int64_t count) {
    try {
        using namespace winrt::Windows::Storage::Streams;
        using namespace winrt::Windows::ApplicationModel::DataTransfer;
        if (!png || count <= 0 || count > MAXDWORD) return;
        auto bytes = std::make_shared<Bytes>(png, png + count);
        DataPackage package;
        package.SetDataProvider(StandardDataFormats::Bitmap(), [bytes](DataProviderRequest const &request) {
            provideImage(request, bytes);
        });
        Clipboard::SetContent(package);
    } catch (...) { report("copying an image"); }
}
extern "C" void swiftomniui_winui_copy_html(char const *html, char const *plainText) {
    try {
        using namespace winrt::Windows::ApplicationModel::DataTransfer;
        DataPackage package; package.SetText(text(plainText));
        package.SetHtmlFormat(HtmlFormatHelper::CreateHtmlFormat(text(html)));
        Clipboard::SetContent(package);
    } catch (...) { report("copying rich text"); }
}
