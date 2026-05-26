using System;
using System.Runtime.InteropServices;

namespace Daily_WinUI.Helpers
{
    [ComImport]
    [Guid("770aae78-f26f-4dba-a829-253c83d1b387")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IDXGIFactory1
    {
        [PreserveSig]
        int EnumAdapters(uint Adapter, out IntPtr ppAdapter);
        [PreserveSig]
        int MakeWindowAssociation(IntPtr WindowHandle, uint Flags);
        [PreserveSig]
        int GetWindowAssociation(out IntPtr pWindowHandle);
        [PreserveSig]
        int CreateSwapChain(IntPtr pDevice, ref IntPtr pDesc, out IntPtr ppSwapChain);
        [PreserveSig]
        int CreateSoftwareAdapter(IntPtr Module, out IntPtr ppAdapter);
        [PreserveSig]
        int EnumAdapters1(uint Adapter, out IntPtr ppAdapter);
        [PreserveSig]
        int IsCurrent();
    }

    [ComImport]
    [Guid("29038f61-3839-4626-91fd-086879011a05")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IDXGIAdapter1
    {
        [PreserveSig]
        int EnumOutputs(uint Output, out IntPtr ppOutput);
        [PreserveSig]
        int GetDesc(out DXGI_ADAPTER_DESC pDesc);
        [PreserveSig]
        int CheckInterfaceSupport(ref Guid InterfaceName, out long pUMDVersion);
        [PreserveSig]
        int GetDesc1(out DXGI_ADAPTER_DESC1 pDesc);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DXGI_ADAPTER_DESC
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public uint AdapterLuidLow;
        public int AdapterLuidHigh;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DXGI_ADAPTER_DESC1
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public uint AdapterLuidLow;
        public int AdapterLuidHigh;
        public uint Flags;
    }

    public static class DeviceHelper
    {
        [DllImport("dxgi.dll", SetLastError = true)]
        private static extern int CreateDXGIFactory1(ref Guid riid, out IDXGIFactory1 ppFactory);

        public static int GetAdapterIndex(string type)
        {
            try
            {
                Guid factoryGuid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
                int hr = CreateDXGIFactory1(ref factoryGuid, out IDXGIFactory1 factory);
                if (hr != 0)
                {
                    System.Diagnostics.Debug.WriteLine($"[DeviceHelper] CreateDXGIFactory1 failed with HR: 0x{hr:X}");
                    return 0;
                }

                uint index = 0;
                while (true)
                {
                    IntPtr adapterPtr = IntPtr.Zero;
                    hr = factory.EnumAdapters1(index, out adapterPtr);
                    if (hr != 0 || adapterPtr == IntPtr.Zero)
                    {
                        break;
                    }

                    try
                    {
                        var adapter = (IDXGIAdapter1)Marshal.GetObjectForIUnknown(adapterPtr);
                        hr = adapter.GetDesc1(out DXGI_ADAPTER_DESC1 desc);
                        if (hr == 0)
                        {
                            string descStr = desc.Description ?? "";
                            System.Diagnostics.Debug.WriteLine($"[DeviceHelper] Adapter {index}: {descStr}");
                            
                            if (type.Equals("NPU", StringComparison.OrdinalIgnoreCase))
                            {
                                if (descStr.Contains("NPU", StringComparison.OrdinalIgnoreCase) ||
                                    descStr.Contains("AI Boost", StringComparison.OrdinalIgnoreCase) ||
                                    descStr.Contains("IPU", StringComparison.OrdinalIgnoreCase) ||
                                    descStr.Contains("Ryzen AI", StringComparison.OrdinalIgnoreCase))
                                {
                                    System.Diagnostics.Debug.WriteLine($"[DeviceHelper] Found NPU at index {index}: {descStr}");
                                    return (int)index;
                                }
                            }
                            else if (type.Equals("GPU", StringComparison.OrdinalIgnoreCase))
                            {
                                if (!descStr.Contains("NPU", StringComparison.OrdinalIgnoreCase) &&
                                    !descStr.Contains("AI Boost", StringComparison.OrdinalIgnoreCase) &&
                                    !descStr.Contains("IPU", StringComparison.OrdinalIgnoreCase) &&
                                    !descStr.Contains("Microsoft Basic Render", StringComparison.OrdinalIgnoreCase))
                                {
                                    System.Diagnostics.Debug.WriteLine($"[DeviceHelper] Found GPU at index {index}: {descStr}");
                                    return (int)index;
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"[DeviceHelper] Error querying adapter {index}: {ex.Message}");
                    }
                    finally
                    {
                        if (adapterPtr != IntPtr.Zero)
                        {
                            Marshal.Release(adapterPtr);
                        }
                    }

                    index++;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DeviceHelper] Error enumerating adapters: {ex.Message}");
            }

            return 0; // Default fallback to 0
        }
    }
}
