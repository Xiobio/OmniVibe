using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace CodeManager;

public enum AudioCue { Switch, Capture, Remove, Expand, Collapse, InventoryOpen, InventoryClose, Arrange, Restore, Reorder, Waiting, Ready, Error, Detent }

/// <summary>
/// Original themed PCM cues, mixed on a private background thread. No UI dispatch,
/// player process, blocking playback, or deferred playback queue. Public calls only
/// replace a bounded pending request. Output latency is three 256-frame buffers.
/// </summary>
public static class GameAudio
{
    private const int Rate = 44100, Frames = 256, MaxVoices = 4;
    private static readonly object Gate = new();
    private static readonly AutoResetEvent Wake = new(false);
    private static readonly List<Request> Pending = new();
    private static readonly Dictionary<string, long> Last = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, Sample> Cache = new(StringComparer.OrdinalIgnoreCase);
    private static Thread? _thread;
    private static bool _enabled = true, _shutdown;
    private static double _volume = .45;
    private static int _generation;
    private static string? _lastError;
    private static int _activeVoices;
    private static bool _outputOpen;
    public static string? LastError => Volatile.Read(ref _lastError);
    public static (int ActiveVoices, int PendingRequests, bool OutputOpen, int CachedSounds) Diagnostics
    { get { lock (Gate) return (Volatile.Read(ref _activeVoices), Pending.Count, Volatile.Read(ref _outputOpen), Cache.Count); } }
    public static string CustomRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodeManager", "Audio");

    public static void Configure(bool enabled, double volume = .45, bool immersive = false)
    {
        lock (Gate)
        {
            _enabled = enabled; _volume = SafeVolume(volume);
            if (!enabled || _volume == 0) { _generation++; Pending.Clear(); Last.Clear(); }
        }
        Wake.Set();
    }

    public static void Play(Skin skin, AudioCue cue, bool enabled, double volume = .45, bool immersive = false, string? identity = null)
    {
        // A per-action flag may silence, but cannot undo Configure(false). Only an
        // explicit master Configure(true) re-enables normal feedback.
        if (!enabled || SafeVolume(volume) == 0) { Stop(); return; }
        lock (Gate) { if (!_enabled) return; _volume = SafeVolume(volume); }
        if (!immersive && !QuietCue(cue)) return;
        Submit(skin, cue, false, volume, immersive, identity);
    }

    /// <summary>Explicit audition; works while normal feedback is disabled. New preview replaces the previous preview.</summary>
    public static void Preview(Skin skin, AudioCue cue, double volume = .45, bool immersive = true, string? identity = null)
    {
        if (SafeVolume(volume) > 0) Submit(skin, cue, true, volume, immersive, identity);
    }

    /// <summary>Cancels pending requests synchronously; wakes the worker to reset and close native output (normally under 20 ms, validated under 80 ms).</summary>
    public static void Stop()
    {
        lock (Gate) { _generation++; Pending.Clear(); Last.Clear(); }
        Wake.Set();
    }

    /// <summary>Call at application exit. Background output is also released automatically on process exit.</summary>
    public static void Shutdown()
    {
        lock (Gate) { _shutdown = true; _generation++; Pending.Clear(); }
        Wake.Set();
    }

    public static string OverrideDirectory(Skin skin, string? identity = null)
    {
        string folder = Path.Combine(CustomRoot, SkinCatalog.Get(skin).Slug);
        return string.IsNullOrWhiteSpace(identity) ? folder : Path.Combine(folder, SafeIdentity(identity));
    }

    /// <summary>Per-item override, then per-theme override, then the distributed original cue.</summary>
    public static string GetPath(Skin skin, AudioCue cue, string? identity = null)
    {
        string file = cue.ToString().ToLowerInvariant() + ".wav";
        if (!string.IsNullOrWhiteSpace(identity))
        {
            string item = Path.Combine(OverrideDirectory(skin, identity), file);
            if (File.Exists(item)) return item;
        }
        string theme = Path.Combine(OverrideDirectory(skin), file);
        return File.Exists(theme) ? theme : BuiltInPath(skin, cue);
    }

    /// <summary>WAV bytes for compatibility and tooling. Validates custom data and safely falls back to the built-in cue.</summary>
    public static byte[] ReadCue(Skin skin, AudioCue cue, string? identity = null)
    {
        string path = GetPath(skin, cue, identity);
        try { byte[] bytes = File.ReadAllBytes(path); _ = Decode(bytes); return bytes; }
        catch (Exception) when (!string.Equals(path, BuiltInPath(skin, cue), StringComparison.OrdinalIgnoreCase))
        { return File.ReadAllBytes(BuiltInPath(skin, cue)); }
    }

    /// <summary>Copy a user-provided PCM16 WAV (mono/stereo, 16–96 kHz, at most 3 s). Never edits the source.</summary>
    public static string ImportOverride(Skin skin, AudioCue cue, string sourcePath, string? identity = null)
    {
        byte[] bytes = File.ReadAllBytes(sourcePath); _ = Decode(bytes);
        string folder = OverrideDirectory(skin, identity); Directory.CreateDirectory(folder);
        string target = Path.Combine(folder, cue.ToString().ToLowerInvariant() + ".wav");
        string temporary = target + ".tmp"; File.WriteAllBytes(temporary, bytes); File.Move(temporary, target, true);
        lock (Gate) Cache.Remove(target);
        return target;
    }

    public static bool ValidateWave(string path, out string error)
    {
        try { _ = Decode(File.ReadAllBytes(path)); error = ""; return true; }
        catch (Exception exception) { error = exception.Message; return false; }
    }

    public static void RemoveOverride(Skin skin, AudioCue cue, string? identity = null) => ResetOverride(skin, cue, identity);

    public static void ResetOverride(Skin skin, AudioCue cue, string? identity = null)
    {
        string target = Path.Combine(OverrideDirectory(skin, identity), cue.ToString().ToLowerInvariant() + ".wav");
        if (File.Exists(target)) File.Delete(target);
        lock (Gate) Cache.Remove(target);
    }

    private static string BuiltInPath(Skin skin, AudioCue cue) => Path.Combine(AppContext.BaseDirectory, "skins", "audio", SkinCatalog.Get(skin).Slug, cue.ToString().ToLowerInvariant() + ".wav");
    private static string SafeIdentity(string identity)
    {
        if (identity.Length is > 0 and <= 80 && identity.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_')) return identity;
        return "item-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity))).Substring(0, 20).ToLowerInvariant();
    }
    private static double SafeVolume(double volume) => double.IsFinite(volume) ? Math.Clamp(volume, 0, 1) : .45;
    private static bool QuietCue(AudioCue cue) => cue is AudioCue.Switch or AudioCue.Capture or AudioCue.Remove or AudioCue.Waiting or AudioCue.Ready or AudioCue.Error;
    private static int Priority(AudioCue cue) => cue is AudioCue.Waiting or AudioCue.Ready or AudioCue.Error ? 3 : cue == AudioCue.Detent ? 0 : 1;
    private sealed record Request(Skin Skin, AudioCue Cue, bool Preview, double Volume, bool Immersive, string? Identity, int Generation, long Submitted);
    private sealed record Sample(float[] Data, DateTime Changed, long Length);
    private sealed class Voice
    {
        public required float[] Data; public int Position, Limit; public double Volume; public bool Preview; public int Priority;
    }

    private static void Submit(Skin skin, AudioCue cue, bool preview, double volume, bool immersive, string? identity)
    {
        lock (Gate)
        {
            if (_shutdown) return;
            long now = Stopwatch.GetTimestamp();
            string key = $"{skin}:{cue}:{identity}";
            int debounce = cue == AudioCue.Detent ? 65 : cue == AudioCue.Switch ? 70 : Priority(cue) == 3 ? 1500 : 110;
            if (!preview && Last.TryGetValue(key, out long then) && Stopwatch.GetElapsedTime(then, now).TotalMilliseconds < debounce) return;
            if (Last.Count > 128) Last.Clear(); Last[key] = now;
            // No backlog: a newer navigation replaces pending navigation. A newer
            // notification replaces the same item, leaving at most two priorities.
            Pending.RemoveAll(r => preview ? r.Preview : !r.Preview && (Priority(r.Cue) <= Priority(cue) || (Priority(cue) == 3 && Priority(r.Cue) == 3 && r.Identity == identity)));
            if (Pending.Count >= 4) Pending.RemoveAt(0);
            Pending.Add(new(skin, cue, preview, SafeVolume(volume), immersive, identity, _generation, now));
            if (_thread == null)
            {
                _thread = new Thread(Worker) { IsBackground = true, Name = "OmniVibe themed audio" };
                _thread.Start();
            }
        }
        Wake.Set();
    }

    private static Sample Load(Request request)
    {
        string path = GetPath(request.Skin, request.Cue, request.Identity);
        Sample? sample;
        var file = new FileInfo(path);
        lock (Gate) if (Cache.TryGetValue(path, out sample) && sample.Changed == file.LastWriteTimeUtc && sample.Length == file.Length) return sample;
        float[] data;
        try { data = Decode(File.ReadAllBytes(path)); }
        catch (Exception) when (!string.Equals(path, BuiltInPath(request.Skin, request.Cue), StringComparison.OrdinalIgnoreCase))
        { path = BuiltInPath(request.Skin, request.Cue); file = new FileInfo(path); data = Decode(File.ReadAllBytes(path)); }
        sample = new(data, file.LastWriteTimeUtc, file.Length);
        lock (Gate) { if (Cache.Count > 100) Cache.Clear(); Cache[path] = sample; }
        return sample;
    }

    /// <summary>Strict RIFF chunk bounds, PCM16 only, linear resampling, click-safe edges.</summary>
    private static float[] Decode(byte[] bytes)
    {
        if (bytes.Length < 44 || bytes.Length > 1_200_000) throw new InvalidDataException("WAV must be PCM16 mono/stereo, at most 3 seconds.");
        using var reader = new BinaryReader(new MemoryStream(bytes), Encoding.ASCII);
        if (new string(reader.ReadChars(4)) != "RIFF") throw new InvalidDataException("Expected RIFF WAV.");
        _ = reader.ReadUInt32(); if (new string(reader.ReadChars(4)) != "WAVE") throw new InvalidDataException("Expected WAVE.");
        int channels = 0, rate = 0, bits = 0, dataAt = 0, dataBytes = 0, format = 0;
        while (reader.BaseStream.Position + 8 <= bytes.Length)
        {
            string id = new(reader.ReadChars(4)); uint length = reader.ReadUInt32(); long start = reader.BaseStream.Position;
            if (length > bytes.Length - start) throw new InvalidDataException("Truncated WAV chunk.");
            if (id == "fmt " && length >= 16)
            {
                format = reader.ReadUInt16(); channels = reader.ReadUInt16(); rate = reader.ReadInt32(); _ = reader.ReadInt32(); _ = reader.ReadUInt16(); bits = reader.ReadUInt16();
            }
            else if (id == "data") { dataAt = (int)start; dataBytes = (int)length; }
            reader.BaseStream.Position = Math.Min(bytes.Length, start + length + (length & 1));
        }
        if (format != 1 || channels is < 1 or > 2 || bits != 16 || rate is < 16000 or > 96000 || dataAt == 0 || dataBytes % (channels * 2) != 0)
            throw new InvalidDataException("Use uncompressed 16-bit PCM WAV, mono/stereo, 16–96 kHz.");
        int sourceFrames = dataBytes / (channels * 2);
        if (sourceFrames < rate / 100 || sourceFrames > rate * 3) throw new InvalidDataException("WAV duration must be 0.01–3 seconds.");
        int frames = (int)((long)sourceFrames * Rate / rate); var output = new float[frames * 2];
        for (int frame = 0; frame < frames; frame++)
        {
            double src = frame * (double)rate / Rate; int a = Math.Min((int)src, sourceFrames - 1), b = Math.Min(a + 1, sourceFrames - 1); double mix = src - a;
            double edge = Math.Min(1, Math.Min(frame, frames - frame - 1) / 160d);
            for (int channel = 0; channel < 2; channel++)
            {
                int c = Math.Min(channel, channels - 1);
                short va = BitConverter.ToInt16(bytes, dataAt + (a * channels + c) * 2), vb = BitConverter.ToInt16(bytes, dataAt + (b * channels + c) * 2);
                output[frame * 2 + channel] = (float)((va + (vb - va) * mix) / 32768 * edge);
            }
        }
        return output;
    }

    private static void Worker()
    {
        IntPtr device = IntPtr.Zero;
        var buffers = new List<OutputBuffer>(); var voices = new List<Voice>(); int generation = -1; long idleSince = 0;
        try
        {
            while (true)
            {
                Request[] requests; bool enabled, shutdown; double master; int current;
                lock (Gate) { requests = Pending.ToArray(); Pending.Clear(); enabled = _enabled; master = _volume; current = _generation; shutdown = _shutdown; }
                if (generation != current)
                {
                    voices.Clear(); CloseOutput(ref device, buffers); generation = current;
                }
                if (shutdown) break;
                foreach (Request request in requests)
                {
                    if (request.Generation != current || (!request.Preview && !enabled) || Stopwatch.GetElapsedTime(request.Submitted).TotalMilliseconds > 220) continue;
                    try
                    {
                        Sample sample = Load(request);
                        lock (Gate) if (request.Generation != _generation || (!request.Preview && !_enabled)) continue;
                        if (request.Preview) voices.RemoveAll(v => v.Preview);
                        else if (Priority(request.Cue) >= 1) voices.RemoveAll(v => !v.Preview && v.Priority < 3);
                        if (voices.Count >= MaxVoices) voices.RemoveAt(0);
                        int maxFrames = request.Immersive ? sample.Data.Length / 2 : (int)(Rate * (Priority(request.Cue) == 3 ? .6 : request.Cue == AudioCue.Switch ? .14 : .20));
                        voices.Add(new Voice { Data = sample.Data, Limit = Math.Min(sample.Data.Length, maxFrames * 2), Volume = request.Preview ? request.Volume : 1, Preview = request.Preview, Priority = Priority(request.Cue) });
                    }
                    catch (Exception error) { Volatile.Write(ref _lastError, error.Message); }
                }
                Volatile.Write(ref _activeVoices, voices.Count);
                if (voices.Count == 0)
                {
                    if (device != IntPtr.Zero)
                    {
                        if (idleSince == 0) idleSince = Stopwatch.GetTimestamp();
                        // Let the final 17 ms drain, then release the endpoint.
                        // After release the worker blocks, with no silent buffer loop.
                        if (Stopwatch.GetElapsedTime(idleSince).TotalMilliseconds >= 800) CloseOutput(ref device, buffers);
                    }
                    Wake.WaitOne(device == IntPtr.Zero ? Timeout.Infinite : 100); continue;
                }
                idleSince = 0;
                if (device == IntPtr.Zero)
                {
                    var format = new WaveFormat { FormatTag = 1, Channels = 2, SamplesPerSec = Rate, AvgBytesPerSec = Rate * 4, BlockAlign = 4, BitsPerSample = 16 };
                    int result = waveOutOpen(out device, unchecked((uint)-1), ref format, IntPtr.Zero, IntPtr.Zero, 0);
                    if (result != 0) { device = IntPtr.Zero; voices.Clear(); Volatile.Write(ref _lastError, "Audio output unavailable (waveOut " + result + ")."); continue; }
                    for (int i = 0; i < 3; i++) buffers.Add(new OutputBuffer(device));
                    Volatile.Write(ref _outputOpen, true);
                    Volatile.Write(ref _lastError, null);
                }
                foreach (OutputBuffer buffer in buffers)
                {
                    if (buffer.Busy || voices.Count == 0) continue;
                    var mix = new float[Frames * 2];
                    foreach (Voice voice in voices)
                    {
                        double gain = voice.Volume * (voice.Preview ? 1 : master);
                        if (voice.Priority < 3 && voices.Any(v => v.Priority == 3)) gain *= .38;
                        int count = Math.Min(mix.Length, voice.Limit - voice.Position);
                        for (int i = 0; i < count; i++)
                        {
                            double tail = Math.Min(1, (voice.Limit - voice.Position - i) / 700d);
                            mix[i] += (float)(voice.Data[voice.Position + i] * gain * tail);
                        }
                        voice.Position += count;
                    }
                    voices.RemoveAll(v => v.Position >= v.Limit);
                    // Smooth soft limiter protects imported WAV overlap; no hard clipping.
                    var pcm = new short[mix.Length];
                    for (int i = 0; i < mix.Length; i++) pcm[i] = (short)Math.Round(Math.Tanh(mix[i]) * 30000);
                    buffer.Write(device, pcm);
                }
                Volatile.Write(ref _activeVoices, voices.Count);
                // Keep checking reset even during long imported cues. No STA/UI waits.
                Wake.WaitOne(3);
            }
        }
        catch (Exception error) { Volatile.Write(ref _lastError, error.Message); }
        finally
        {
            CloseOutput(ref device, buffers);
            Volatile.Write(ref _activeVoices, 0); Volatile.Write(ref _outputOpen, false);
            lock (Gate) { _thread = null; Pending.Clear(); }
        }
    }

    private static void CloseOutput(ref IntPtr device, List<OutputBuffer> buffers)
    {
        if (device == IntPtr.Zero) return;
        waveOutReset(device);
        foreach (OutputBuffer buffer in buffers) buffer.Release(device);
        buffers.Clear(); waveOutClose(device); device = IntPtr.Zero;
        Volatile.Write(ref _outputOpen, false);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    private struct WaveFormat { public ushort FormatTag, Channels; public uint SamplesPerSec, AvgBytesPerSec; public ushort BlockAlign, BitsPerSample, ExtraSize; }
    [StructLayout(LayoutKind.Sequential)]
    private struct WaveHeader { public IntPtr Data; public uint BufferLength, BytesRecorded; public UIntPtr User; public uint Flags, Loops; public IntPtr Next; public UIntPtr Reserved; }
    private sealed class OutputBuffer
    {
        private readonly IntPtr _data = Marshal.AllocHGlobal(Frames * 4);
        private readonly IntPtr _header = Marshal.AllocHGlobal(Marshal.SizeOf<WaveHeader>());
        private bool _written;
        public OutputBuffer(IntPtr device)
        {
            try
            {
                Marshal.StructureToPtr(new WaveHeader { Data = _data, BufferLength = Frames * 4 }, _header, false);
                int result = waveOutPrepareHeader(device, _header, (uint)Marshal.SizeOf<WaveHeader>());
                if (result != 0) throw new InvalidOperationException("Cannot prepare audio buffer (" + result + ").");
            }
            catch { Marshal.FreeHGlobal(_header); Marshal.FreeHGlobal(_data); throw; }
        }
        public bool Busy => _written && (Marshal.PtrToStructure<WaveHeader>(_header).Flags & 1) == 0;
        public void Write(IntPtr device, short[] pcm)
        {
            Marshal.Copy(pcm, 0, _data, pcm.Length);
            int result = waveOutWrite(device, _header, (uint)Marshal.SizeOf<WaveHeader>());
            if (result != 0) throw new InvalidOperationException("Cannot submit audio buffer (" + result + ").");
            _written = true;
        }
        public void Release(IntPtr device) { waveOutUnprepareHeader(device, _header, (uint)Marshal.SizeOf<WaveHeader>()); Marshal.FreeHGlobal(_header); Marshal.FreeHGlobal(_data); }
    }
    [DllImport("winmm.dll")] private static extern int waveOutOpen(out IntPtr handle, uint device, ref WaveFormat format, IntPtr callback, IntPtr instance, uint flags);
    [DllImport("winmm.dll")] private static extern int waveOutPrepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] private static extern int waveOutUnprepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] private static extern int waveOutWrite(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] private static extern int waveOutReset(IntPtr handle);
    [DllImport("winmm.dll")] private static extern int waveOutClose(IntPtr handle);
}
