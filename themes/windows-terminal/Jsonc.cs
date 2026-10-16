using System;
using System.Text;

// Windows Terminal settings use JSONC. Strip comments and trailing commas only
// outside strings; URLs, escaped quotes and comment-like command arguments survive.
public static class OmniVibeJsonc
{
    public static string Normalize(string source)
    {
        if (source == null) throw new ArgumentNullException("source");
        source = source.TrimStart('\uFEFF');
        var output = new StringBuilder(source.Length);
        bool quoted = false, escaped = false;
        for (int i = 0; i < source.Length; i++)
        {
            char c = source[i];
            if (quoted)
            {
                output.Append(c);
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == '"') quoted = false;
                continue;
            }
            if (c == '"') { quoted = true; output.Append(c); continue; }
            if (c == '/' && i + 1 < source.Length && source[i + 1] == '/')
            {
                output.Append("  "); i++;
                while (i + 1 < source.Length && source[i + 1] != '\r' && source[i + 1] != '\n') { output.Append(' '); i++; }
                continue;
            }
            if (c == '/' && i + 1 < source.Length && source[i + 1] == '*')
            {
                output.Append("  "); i++;
                bool ended = false;
                while (++i < source.Length)
                {
                    if (source[i] == '*' && i + 1 < source.Length && source[i + 1] == '/') { output.Append("  "); i++; ended = true; break; }
                    output.Append(source[i] == '\r' || source[i] == '\n' ? source[i] : ' ');
                }
                if (!ended) throw new FormatException("Unterminated JSONC block comment.");
                continue;
            }
            output.Append(c);
        }
        if (quoted) throw new FormatException("Unterminated JSON string.");
        char[] cleaned = output.ToString().ToCharArray();
        quoted = escaped = false;
        for (int i = 0; i < cleaned.Length; i++)
        {
            char c = cleaned[i];
            if (quoted)
            {
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == '"') quoted = false;
                continue;
            }
            if (c == '"') { quoted = true; continue; }
            if (c != ',') continue;
            int next = i + 1;
            while (next < cleaned.Length && Char.IsWhiteSpace(cleaned[next])) next++;
            if (next < cleaned.Length && (cleaned[next] == '}' || cleaned[next] == ']'))
            {
                int previous = i - 1;
                while (previous >= 0 && Char.IsWhiteSpace(cleaned[previous])) previous--;
                if (previous < 0 || cleaned[previous] == ',' || cleaned[previous] == ':' || cleaned[previous] == '[' || cleaned[previous] == '{')
                    throw new FormatException("Unexpected comma in JSONC.");
                cleaned[i] = ' ';
            }
        }
        return new string(cleaned);
    }
}
