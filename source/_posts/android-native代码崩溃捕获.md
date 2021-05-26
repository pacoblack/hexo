---
title: android native代码崩溃捕获
toc: true
date: 2021-05-26 16:22:51
tags:
- Android
categories:
- Android
---
捕获native异常栈
<!--more-->
#订阅异常发生的信号
```c++
extern int sigaction(int, const struct sigaction*, struct sigaction*);
```

# 设置额外栈空间
```c++
#include <signal.h>
int sigaltstack(const stack_t *ss, stack_t *oss);
```

# 捕获Crash位置
```c++
const int signal_array[] = {SIGILL, SIGABRT, SIGBUS, SIGFPE, SIGSEGV, SIGSTKFLT, SIGSYS};

void signal_handle(int code, siginfo_t *si, void *context) {
}

void init() {
    struct sigaction old_signal_handlers[SIGNALS_LEN];

    struct sigaction handler;
    handler.sa_sigaction = signal_handle;
    handler.sa_flags = SA_SIGINFO;

    for (int i = 0; i < SIGNALS_LEN; ++i) {
        sigaction(signal_array[i], &handler, & old_signal_handlers[i]);
    }
}
```
`signal_handle()` 函数中的第三个参数 `context` 是 `uc_mcontext` 的结构体指针，它封装了 cpu 相关的上下文，包括当前线程的寄存器信息和奔溃时的 pc 值，能够知道崩溃时的pc，就能知道崩溃时执行的是那条指令.
不过uc_mcontext结构体的定义是平台相关的，比如我们熟知的arm、x86这种都不是同一个结构体定义，上面的代码只列出了arm架构的寄存器信息，要兼容其他架构的 cpu 在处理的时候，就得要寄出宏编译大法，不同的架构使用不同的定义。
```C++
uintptr_t pc_from_ucontext(const ucontext_t *uc) {
#if (defined(__arm__))
    return uc->uc_mcontext.arm_pc;
#elif defined(__aarch64__)
    return uc->uc_mcontext.pc;
#elif (defined(__x86_64__))
    return uc->uc_mcontext.gregs[REG_RIP];
#elif (defined(__i386))
  return uc->uc_mcontext.gregs[REG_EIP];
#elif (defined (__ppc__)) || (defined (__powerpc__))
  return uc->uc_mcontext.regs->nip;
#elif (defined(__hppa__))
  return uc->uc_mcontext.sc_iaoq[0] & ~0x3UL;
#elif (defined(__sparc__) && defined (__arch64__))
  return uc->uc_mcontext.mc_gregs[MC_PC];
#elif (defined(__sparc__) && !defined (__arch64__))
  return uc->uc_mcontext.gregs[REG_PC];
#else
#error "Architecture is unknown, please report me!"
#endif
}
```
获取到的pc值是程序加载到内存中的绝对地址，绝对地址不能直接使用，因为每次程序运行创建的内存肯定都不是固定区域的内存，所以绝对地址肯定每次运行都不一致。我们需要拿到崩溃代码相对于当前库的相对偏移地址，这样才能使用 `addr2line` 分析出是哪一行代码。通过`dladdr()`可以获得共享库加载到内存的起始地址，和pc值相减就可以获得相对偏移地址，并且可以获得共享库的名字。

# 获取的crash的堆栈
获取函数调用栈是最麻烦的，至今没有一个好用的，全都要做一些大改动。常见的做法有四种：

- 第一种：直接使用系统的<unwind.h>库，可以获取到出错文件与函数名。只不过需要自己解析函数符号，同时经常会捕获到系统错误，需要手动过滤。
- 第二种：在4.1.1以上，5.0以下，使用系统自带的libcorkscrew.so，5.0开始，系统中没有了libcorkscrew.so，可以自己编译系统源码中的libunwind。libunwind是一个开源库，事实上高版本的安卓源码中就使用了他的优化版替换libcorkscrew。
- 第三种：使用开源库coffeecatch，但是这种方案也不能百分之百兼容所有机型。
- 第四种：使用 Google 的breakpad，这是所有 C/C++堆栈获取的权威方案，基本上业界都是基于这个库来做的。只不过这个库是全平台的 android、iOS、Windows、Linux、MacOS 全都有，所以非常大，在使用的时候得把无关的平台剥离掉减小体积。

下面以第一种为例讲一下实现：
核心方法是使用`<unwind.h>`库提供的一个方法`_Unwind_Backtrace()`这个函数可以传入一个函数指针作为回调，指针指向的函数有一个重要的参数是`_Unwind_Context`类型的结构体指针。
可以使用`_Unwind_GetIP()`函数将当前函数调用栈中每个函数的绝对内存地址（也就是上文中提到的 pc 值），写入到`_Unwind_Context`结构体中，最终返回的是当前调用栈的全部函数地址了，`_Unwind_Word`实际上就是一个unsigned int。
而`capture_backtrace()`返回的就是当前我们获取到调用栈中内容的数量。

```C++
/**
 * callback used when using <unwind.h> to get the trace for the current context
 */
_Unwind_Reason_Code unwind_callback(struct _Unwind_Context *context, void *arg) {
    backtrace_state_t *state = (backtrace_state_t *) arg;
    _Unwind_Word pc = _Unwind_GetIP(context);
    if (pc) {
        if (state->current == state->end) {
            return _URC_END_OF_STACK;
        } else {
            *state->current++ = (void *) pc;
        }
    }
    return _URC_NO_REASON;
}

/**
 * uses built in <unwind.h> to get the trace for the current context
 */
size_t capture_backtrace(void **buffer, size_t max) {
    backtrace_state_t state = {buffer, buffer + max};
    _Unwind_Backtrace(unwind_callback, &state);
    return state.current - buffer;
}
```
当所有的函数的绝对内存地址(pc 值)都获取到了，就可以用上文讲的办法将 pc 值转换为相对偏移量，获取到真正的函数信息和相对内存地址了。
```C++
void *buffer[max_line];
int frames_size = capture_backtrace(buffer, max_line);
for (int i = 0; i < frames_size; i++) {
    Dl_info info;  
    const void *addr = buffer[i];
    if (dladdr(addr, &info) && info.dli_fname) {  
      void * const nearest = info.dli_saddr;  
      uintptr_t addr_relative = addr - info.dli_fbase;  
}
```
Dl_info是一个结构体，内部封装了函数所在文件、函数名、当前库的基地址等信息

```C++
typedef struct {
    const char *dli_fname;  /* Pathname of shared object that
                               contains address */
    void       *dli_fbase;  /* Address at which shared object
                               is loaded */
    const char *dli_sname;  /* Name of nearest symbol with address
                               lower than addr */
    void       *dli_saddr;  /* Exact address of symbol named
                               in dli_sname */
} Dl_info;
```
有了这个对象，我们就能获取到全部想要的信息了。虽然获取到全部想要的信息，但<unwind.h>有个麻烦的就是不想要的信息也给你了，所以需要手动过滤掉各种系统错误，最终得到的数据，就可以上报到自己的服务器了。

# 获取当前java堆栈
我们认为crash线程就是捕获到信号的线程，虽然这在SIGABRT下不一定可靠。在信号处理函数中获得当前线程的名字，然后把crash线程的名字传给java层，在java里dump出这个线程的堆栈，就是crash所对应的java层堆栈了。

在c中获得线程名字：
```C
char* getThreadName(pid_t tid) {
    if (tid <= 1) {
        return NULL;
    }
    char* path = (char *) calloc(1, 80);
    char* line = (char *) calloc(1, THREAD_NAME_LENGTH);

    snprintf(path, PATH_MAX, "proc/%d/comm", tid);
    FILE* commFile = NULL;
    if (commFile = fopen(path, "r")) {
        fgets(line, THREAD_NAME_LENGTH, commFile);
        fclose(commFile);
    }
    free(path);
    if (line) {
        int length = strlen(line);
        if (line[length - 1] == '\n') {
            line[length - 1] = '\0';
        }
    }
    return line;
}
```
然后传给java层：
```C
    /**
     * 根据线程名获得线程对象，native层会调用该方法，不能混淆
     * @param threadName
     * @return
     */
    @Keep
    public static Thread getThreadByName(String threadName) {
        if (TextUtils.isEmpty(threadName)) {
            return null;
        }

        Set<Thread> threadSet = Thread.getAllStackTraces().keySet();
        Thread[] threadArray = threadSet.toArray(new Thread[threadSet.size()]);

        Thread theThread = null;
        for(Thread thread : threadArray) {
            if (thread.getName().equals(threadName)) {
                theThread =  thread;
            }
        }

        Log.d(TAG, "threadName: " + threadName + ", thread: " + theThread);
        return theThread;
    }
```

# 防止死锁或者死循环
首先我们要了解async-signal-safe和可重入函数概念：

>A signal handler function must be very careful, since processing elsewhere may be interrupted at some arbitrary point in the execution of the program.
POSIX has the concept of “safe function”.  If a signal interrupts the execution of an unsafe function, and handler  either calls an unsafe function or handler terminates via a call to longjmp() or siglongjmp() and the program subsequently calls an unsafe function, then the behavior of the program is undefined.

进程捕捉到信号并对其进行处理时，进程正在执行的正常指令序列就被信号处理程序临时中断，它首先执行该信号处理程序中的指令（类似发生硬件中断）。但在信号处理程序中，不能判断捕捉到信号时进程执行到何处。如果进程正在执行malloc，在其堆中分配另外的存储空间，而此时由于捕捉到信号而插入执行该信号处理程序，其中又调用malloc，这时会发生什么？这可能会对进程造成破坏，因为malloc通常为它所分配的存储区维护一个链表，而插入执行信号处理程序时，进程可能正在更改此链表。（参考《UNIX环境高级编程》）

Single UNIX Specification说明了在信号处理程序中保证调用安全的函数。这些函数是可重入的并被称为是异步信号安全（async-signal-safe）。除了可重入以外，在信号处理操作期间，它会阻塞任何会引起不一致的信号发送。
但即使我们自己在信号处理程序中不使用不可重入的函数，也无法保证保存的旧的信号处理程序中不会有非异步信号安全的函数。所以要使用alarm保证信号处理程序不会陷入死锁或者死循环的状态。
```C
static void signal_handler(const int code, siginfo_t *const si,
                                    void *const sc) {

    /* Ensure we do not deadlock. Default of ALRM is to die.
    * (signal() and alarm() are signal-safe) */
    signal(code, SIG_DFL);
    signal(SIGALRM, SIG_DFL);

    /* Ensure we do not deadlock. Default of ALRM is to die.
      * (signal() and alarm() are signal-safe) */
    (void) alarm(8);
    ....
}
```
参考资料：
https://www.kymjs.com/code/2018/08/22/01/
https://mp.weixin.qq.com/s/g-WzYF3wWAljok1XjPoo7w
