using System;
using System.Security.Cryptography;
using System.Text;

namespace Daily_WinUI.Helpers
{
    public static class UuidHelper
    {
        /// <summary>
        /// Generates a deterministic UUID (UUIDv5 equivalent) from a given string.
        /// </summary>
        public static Guid GenerateDeterministicGuid(string input)
        {
            if (string.IsNullOrEmpty(input))
                throw new ArgumentNullException(nameof(input));

            using (var md5 = MD5.Create())
            {
                byte[] hash = md5.ComputeHash(Encoding.UTF8.GetBytes(input));
                
                // UUID v5 formatting
                hash[6] &= 0x0f;
                hash[6] |= 0x50; // Version 5
                hash[8] &= 0x3f;
                hash[8] |= 0x80; // Variant 1

                return new Guid(hash);
            }
        }
    }
}
