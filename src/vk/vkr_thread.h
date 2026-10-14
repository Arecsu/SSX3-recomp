/* The few pthread calls the renderer uses (a mutex, a condition variable, one
 * detached thread), on Windows mapped to slim reader/writer locks, condition
 * variables and CreateThread; elsewhere plain <pthread.h>. */
#ifndef VKR_THREAD_H
#define VKR_THREAD_H

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>

typedef SRWLOCK            pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef HANDLE             pthread_t;

#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
#define PTHREAD_COND_INITIALIZER  CONDITION_VARIABLE_INIT

#define pthread_mutex_init(m, a)    (InitializeSRWLock(m), 0)
#define pthread_cond_init(c, a)     (InitializeConditionVariable(c), 0)
#define pthread_mutex_lock(m)       AcquireSRWLockExclusive(m)
#define pthread_mutex_unlock(m)     ReleaseSRWLockExclusive(m)
#define pthread_cond_wait(c, m)     SleepConditionVariableSRW((c), (m), INFINITE, 0)
#define pthread_cond_signal(c)      WakeConditionVariable(c)
#define pthread_cond_broadcast(c)   WakeAllConditionVariable(c)
#define pthread_mutex_destroy(m)    ((void)(m))
#define pthread_cond_destroy(c)     ((void)(c))

typedef struct { void *(*fn)(void *); void *arg; } vkr_thread_start_;

static DWORD WINAPI vkr_thread_tramp_(LPVOID p)
{
    vkr_thread_start_ s = *(vkr_thread_start_ *)p;
    free(p);
    s.fn(s.arg);
    return 0;
}

static int pthread_create(pthread_t *th, void *attr, void *(*fn)(void *), void *arg)
{
    vkr_thread_start_ *s = (vkr_thread_start_ *)malloc(sizeof *s);
    (void)attr;
    if (!s)
        return -1;
    s->fn = fn; s->arg = arg;
    *th = CreateThread(NULL, 0, vkr_thread_tramp_, s, 0, NULL);
    if (!*th) {
        free(s);
        return -1;
    }
    return 0;
}

static int pthread_detach(pthread_t th)
{
    CloseHandle(th);
    return 0;
}

#else
#include <pthread.h>
#endif

#endif
