using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OmniVibeShaderCompiler
{
    [ComImport, Guid("8BA5FB08-5195-40e2-AC58-0D989C3A0102"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface Blob
    {
        [PreserveSig] IntPtr GetBufferPointer();
        [PreserveSig] UIntPtr GetBufferSize();
    }
    [DllImport("d3dcompiler_47.dll", CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
    private static extern int D3DCompile(byte[] source, UIntPtr size, string sourceName, IntPtr defines, IntPtr include, string entry, string target, uint flags1, uint flags2, out Blob code, out Blob errors);

    public static int Validate(string source)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(source);
        Blob code = null, errors = null;
        try
        {
            // Strict language rules and warnings-as-errors for every skin,
            // including the original Ink Jade shader. No runtime compiler cache.
            int result = D3DCompile(bytes, (UIntPtr)bytes.Length, "OmniVibe-terminal-frame.hlsl", IntPtr.Zero, IntPtr.Zero, "main", "ps_4_0", (1u << 11) | (1u << 18), 0, out code, out errors);
            if (result < 0)
            {
                string message = errors == null ? "Unknown HLSL compilation error" : Marshal.PtrToStringAnsi(errors.GetBufferPointer(), (int)errors.GetBufferSize().ToUInt64());
                throw new InvalidOperationException(message);
            }
            return (int)code.GetBufferSize().ToUInt64();
        }
        finally
        {
            if (code != null) Marshal.ReleaseComObject(code);
            if (errors != null) Marshal.ReleaseComObject(errors);
        }
    }
}
