using System;
using System.Security.Cryptography;
using System.Text;

namespace Daily.Services.Auth
{
    public static class EncryptionHelper
    {
        private static readonly byte[] StaticSalt = new byte[] { 0x44, 0x61, 0x69, 0x6c, 0x79, 0x5f, 0x53, 0x65, 0x63, 0x75, 0x72, 0x65, 0x5f, 0x4b, 0x65, 0x79 }; // "Daily_Secure_Key"

        private static byte[] DeriveKey(string userId)
        {
            // Derive a 256-bit key from the Supabase User ID + Static Salt
            #pragma warning disable SYSLIB0041 // Type or member is obsolete in newer .NET, but Rfc2898DeriveBytes is still standard for compatibility.
            using (var pbkdf2 = new Rfc2898DeriveBytes(userId, StaticSalt, 1000, HashAlgorithmName.SHA256))
            {
                return pbkdf2.GetBytes(32); // 256 bits
            }
            #pragma warning restore SYSLIB0041
        }

        public static string Encrypt(string plainText, string userId)
        {
            if (string.IsNullOrEmpty(plainText) || string.IsNullOrEmpty(userId)) return plainText;

            try
            {
                byte[] key = DeriveKey(userId);
                byte[] plainBytes = Encoding.UTF8.GetBytes(plainText);

                // AES-GCM needs 12-byte nonce and 16-byte tag
                byte[] nonce = new byte[12];
                RandomNumberGenerator.Fill(nonce);

                byte[] tag = new byte[16];
                byte[] cipherBytes = new byte[plainBytes.Length];

                using (var aesGcm = new AesGcm(key, 16))
                {
                    aesGcm.Encrypt(nonce, plainBytes, cipherBytes, tag);
                }

                // Format: nonce (12 bytes) + tag (16 bytes) + ciphertext
                byte[] result = new byte[nonce.Length + tag.Length + cipherBytes.Length];
                Buffer.BlockCopy(nonce, 0, result, 0, nonce.Length);
                Buffer.BlockCopy(tag, 0, result, nonce.Length, tag.Length);
                Buffer.BlockCopy(cipherBytes, 0, result, nonce.Length + tag.Length, cipherBytes.Length);

                return Convert.ToBase64String(result);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EncryptionHelper] Encryption failed: {ex.Message}");
                return plainText; // Fallback
            }
        }

        public static string Decrypt(string cipherText, string userId)
        {
            if (string.IsNullOrEmpty(cipherText) || string.IsNullOrEmpty(userId)) return cipherText;

            try
            {
                byte[] key = DeriveKey(userId);
                byte[] encryptedData = Convert.FromBase64String(cipherText);

                if (encryptedData.Length < 28) return cipherText; // Must be at least nonce + tag

                byte[] nonce = new byte[12];
                byte[] tag = new byte[16];
                byte[] cipherBytes = new byte[encryptedData.Length - 28];

                Buffer.BlockCopy(encryptedData, 0, nonce, 0, 12);
                Buffer.BlockCopy(encryptedData, 12, tag, 0, 16);
                Buffer.BlockCopy(encryptedData, 28, cipherBytes, 0, cipherBytes.Length);

                byte[] plainBytes = new byte[cipherBytes.Length];

                using (var aesGcm = new AesGcm(key, 16))
                {
                    aesGcm.Decrypt(nonce, cipherBytes, tag, plainBytes);
                }

                return Encoding.UTF8.GetString(plainBytes);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EncryptionHelper] Decryption failed: {ex.Message}");
                return cipherText; // Return original if not decryptable (e.g. if was unencrypted)
            }
        }
    }
}
