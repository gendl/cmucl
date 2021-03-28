/*

 This code was written as part of the CMU Common Lisp project and has
 been placed in the public domain.

*/
#ifndef __X86_ARCH_H

extern int arch_support_sse2(void);
extern boolean os_support_sse2(void);

/*
 * Set to non-zero to enable debug prints for debugging the sigill and
 * sigtrap handlers and for debugging breakpoints.
 */
extern unsigned int debug_handlers;


/*
 * Define macro to allocate a local array of the appropriate size
 * where the fpu state can be stored.
 */

#define FPU_STATE_SIZE 27

/* 
 * Need 512 byte area, aligned on a 16-byte boundary.
 */
#define SSE_STATE_SIZE 512

/*
 * Just use the SSE size for both x87 and sse2 since the SSE size is
 * enough for either.  Make sure it's on a 16-byte boundary.
 */
#define FPU_STATE(name)    u_int8_t name[SSE_STATE_SIZE] __attribute__((aligned(16)))

#endif
