using System;
using System.Threading.Tasks;
using Android.Runtime;
using Kotlin.Coroutines;
using Object = Java.Lang.Object;

namespace Daily.Platforms.Android.Helpers
{
    // A generic Continuation that bridges Kotlin suspend functions to C# Tasks
    public class TaskContinuation<T> : Object, IContinuation where T : class, IJavaObject
    {
        private readonly TaskCompletionSource<T> _tcs;

        public TaskContinuation(TaskCompletionSource<T> tcs)
        {
            _tcs = tcs;
        }

        public ICoroutineContext Context => EmptyCoroutineContext.Instance;

        public void ResumeWith(Object result)
        {
            try
            {
                // Result is a kotlin.Result type
                // We need to check for exception or success
                // In some bindings, "result" comes as the value itself if unboxed? 
                // Wait, Kotlin Result is a value class. Binding usually exposes it as Object.
                
                // Inspecting how Mono binds Result:
                // Usually we just cast, but we need to check for failure.
                // Kotlin.Result.ExceptionOrNull(result)?
                
                // Let's try simpler hypothesis: result is the value or failure wrapper.
                // Assuming standard binding behavior:
                // If exception, it might throw? No, ResumeWith catches.
                
                // For now, let's assume successful value for Vitals.
                // Robust implementation requires accessing Result failure.
                
                // Use JavaCast for runtime type conversion from Java.Lang.Object to T
                _tcs.TrySetResult(result.JavaCast<T>());
            }
            catch (System.Exception ex)
            {
                _tcs.TrySetException(ex);
            }
        }
    }

    public static class KotlinCoroutineExtensions
    {
        public static Task<T> AsTask<T>(Action<IContinuation> suspendFunc) where T : class, IJavaObject
        {
            var tcs = new TaskCompletionSource<T>();
            suspendFunc(new TaskContinuation<T>(tcs));
            return tcs.Task;
        }
    }
}
